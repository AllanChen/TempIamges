"""Edit the painted area of an image with GPT Image (gpt-image-2.5-flare via guluapi).

Inputs: the original image (task.input.path), a mask PNG URL (parameters.mask) and a text
prompt (parameters.prompt). Glance's mask editor paints the area to change as opaque white on a
transparent PNG. GPT Image regenerates the whole picture, so only the masked area of its result
is kept: the original pixels outside the mask are pasted back with a soft seam.
"""

import argparse
import base64
import io
import json
import logging
import os
import subprocess
import tempfile
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

import requests
from PIL import Image, ImageChops, ImageFilter, ImageOps, ImageStat

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

BASE_URL = "https://guluapi.com"
MODEL = "gpt-image-2.5-flare"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
# Same key source as gpu_task: env var first, then gpu_task/config/config.env.
GPU_TASK_CONFIG = Path(os.environ.get("GULU_CONFIG_ENV", Path.home() / "Desktop/work/gpu_task/config/config.env"))
REQUEST_TIMEOUT = 300
MAX_RETRIES = 3
RETRY_BACKOFF = 5  # seconds between retries
MAX_BYTES = 50 * 1024 * 1024
MAX_PROMPT = 2000
# Used when the task carries no description: just remove whatever is painted.
DEFAULT_PROMPT = "Remove the object in this region and fill it in naturally with the surrounding background."

# The result keeps the original aspect ratio with its long edge clamped to this range.
MAX_LONG_EDGE = 2048
MIN_LONG_EDGE = 1024
GPT_TARGET_PIXELS = 1024 * 1536
GPT_MAX_ASPECT = 3.0
ASPECT_TOLERANCE = 0.03
# Mean per-pixel difference (0-255) between GPT's result and the original outside the mask; a result that
# kept the framing scores low, a reframed or shifted one scores high.
MAX_ALIGNMENT_DIFF = 35
MIN_UNMASKED_SHARE = 0.05  # skip the alignment check when the mask covers almost everything
GROW_RATIO = 0.004  # the pasted region grows slightly past the mask so no original edge pixels survive
FEATHER_RATIO = 0.006  # blur of the seam, relative to the long edge

PROMPT = (
    "Image 1 is the photo to edit. Image 2 is a mask for image 1: the white area marks the region to change "
    "and the black area must stay untouched. Edit only the white region of image 1 as follows: {prompt}\n"
    "Make the edited region blend naturally with the rest of the scene, matching its lighting, perspective, "
    "colors, grain and texture. Keep everything outside the white region exactly the same as image 1, with "
    "the same framing. Output only the edited version of image 1, without any mask, outline or border."
)

GPT_UPLOAD_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
MODERATION_CODES = {"moderation_blocked", "content_policy_violation", "content_filter", "safety_violation"}
MODERATION_KEYWORDS = ("moderation", "safety system", "content policy", "content_policy", "safety_violation",
                       "sensitive", "violat", "审核", "违规", "敏感")


class ModerationRejectedError(Exception):
    """GPT Image rejected the image or prompt in content moderation; retrying will not help."""


class BadResultError(Exception):
    """GPT Image returned a result that cannot be used (reframed or shifted)."""


def get_api_key() -> str:
    """Read GULU_GPTIMAGE_KEY from the environment, else from gpu_task's config.env."""
    key = os.environ.get("GULU_GPTIMAGE_KEY", "")
    if key or not GPU_TASK_CONFIG.is_file():
        return key
    for line in GPU_TASK_CONFIG.read_text(encoding="utf-8").splitlines():
        name, _, value = line.strip().partition("=")
        if name.strip() == "GULU_GPTIMAGE_KEY":
            return value.strip().strip('"').strip("'")
    return ""


def is_moderation_rejection(status_code: int, body) -> bool:
    """Detect an OpenAI-compatible moderation rejection (e.g. error.code == "moderation_blocked")."""
    if status_code not in (400, 403, 422, 451):
        return False
    error = body.get("error") if isinstance(body, dict) else None
    if isinstance(error, dict):
        code = str(error.get("code") or error.get("type") or "").lower()
        if code in MODERATION_CODES:
            return True
        text = str(error.get("message") or "").lower()
    else:
        text = json.dumps(body, ensure_ascii=False).lower() if body else ""
    return any(keyword in text for keyword in MODERATION_KEYWORDS)


def output_size(size: tuple[int, int]) -> tuple[int, int]:
    """Scale (width, height) so the long edge is within [MIN_LONG_EDGE, MAX_LONG_EDGE], keeping the ratio."""
    width, height = size
    long_edge = max(width, height)
    target = min(max(long_edge, MIN_LONG_EDGE), MAX_LONG_EDGE)
    if target == long_edge:
        return size
    scale = target / long_edge
    return max(1, round(width * scale)), max(1, round(height * scale))


def request_size(size: tuple[int, int]) -> str:
    """Pick a GPT output size with the same aspect ratio (multiples of 16)."""
    width, height = size
    scale = (GPT_TARGET_PIXELS / (width * height)) ** 0.5
    return f"{max(16, round(width * scale / 16) * 16)}x{max(16, round(height * scale / 16) * 16)}"


def load_upright(path: Path, work_dir: Path) -> Image.Image:
    """Open an image as RGB (transparency flattened onto white) with EXIF orientation applied."""
    source = path
    if path.suffix.lower() not in GPT_UPLOAD_SUFFIXES:
        source = work_dir / f"converted-{uuid.uuid4().hex}.png"
        subprocess.run(["/usr/bin/sips", "-s", "format", "png", str(path), "--out", str(source)],
                       check=True, capture_output=True, timeout=60)
    with Image.open(source) as image:
        upright = ImageOps.exif_transpose(image).convert("RGBA")
    flattened = Image.new("RGBA", upright.size, (255, 255, 255, 255))
    flattened.alpha_composite(upright)
    return flattened.convert("RGB")


def selected_area(mask: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Turn a mask image into an 'L' image at `size`: 255 where the area to change is, 0 elsewhere.

    Glance paints the area as opaque white on a transparent PNG; a plain black-and-white mask
    (white = change) works too. Masks are stretched to the photo size: the editor's strokes are
    normalized to the whole picture, so a mask exported at the file's raw size still maps correctly.
    """
    rgba = mask.convert("RGBA")
    value = ImageChops.multiply(rgba.getchannel("A"), rgba.convert("L"))
    value = value.resize(size, Image.Resampling.BILINEAR)
    return value.point(lambda v: 255 if v > 127 else 0)


def fetch_mask(url: str) -> Image.Image:
    """Download the mask PNG that the client uploaded."""
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("The mask must be an https URL. Draw or upload the mask again and retry.")
    with requests.get(url, timeout=60, stream=True) as response:
        response.raise_for_status()
        content = bytearray()
        for chunk in response.iter_content(chunk_size=1024 * 1024):
            content += chunk
            if len(content) > MAX_BYTES:
                raise ValueError("The mask image exceeds 50 MB.")
    try:
        with Image.open(io.BytesIO(bytes(content))) as image:
            image.load()
            return image.copy()
    except Exception as error:
        raise ValueError("The mask could not be read as an image. Draw or upload the mask again.") from error


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def request_gpt_image(photo_png: bytes, mask_png: bytes, prompt: str, api_key: str, size: str) -> bytes:
    """Call the GPT Image edits endpoint with the photo and its mask and return the image bytes."""
    headers = {"Authorization": f"Bearer {api_key}", "User-Agent": USER_AGENT}
    data = {"model": MODEL, "prompt": PROMPT.format(prompt=prompt), "output_format": "png", "size": size, "n": "1"}
    logger.info("Submitting masked edit to %s (%s, size=%s) ...", BASE_URL, MODEL, size)
    response = requests.post(
        f"{BASE_URL}/v1/images/edits", headers=headers, data=data,
        files=[("image[]", ("photo.png", photo_png, "image/png")),
               ("image[]", ("mask.png", mask_png, "image/png"))],
        timeout=REQUEST_TIMEOUT,
    )
    try:
        body = response.json()
    except ValueError:
        body = None
    if response.status_code != 200:
        if is_moderation_rejection(response.status_code, body):
            raise ModerationRejectedError(f"GPT Image moderation rejected the request: {body}")
        raise RuntimeError(f"GPT Image error: {response.status_code}, {response.text[:500]}")
    items = (body or {}).get("data") or []
    if not items:
        raise RuntimeError(f"GPT Image returned no image: {str(body)[:500]}")
    item = items[0]
    if item.get("b64_json"):
        return base64.b64decode(item["b64_json"])
    if item.get("url"):
        with requests.get(item["url"], timeout=60) as download:
            download.raise_for_status()
            return download.content
    raise RuntimeError(f"GPT Image result has neither b64_json nor url: {str(item)[:500]}")


def alignment_diff(original: Image.Image, result: Image.Image, keep: Image.Image) -> float:
    """Mean difference between the original and GPT's result over the pixels that should not change."""
    small = (256, max(1, round(256 * original.height / original.width)))
    difference = ImageChops.difference(original.resize(small), result.convert("RGB").resize(small)).convert("L")
    return ImageStat.Stat(difference, keep.resize(small)).mean[0]


def blend_mask(selected: Image.Image) -> Image.Image:
    """Grow the selected area a little and soften its edge for the final paste."""
    long_edge = max(selected.size)
    grow = max(1, round(long_edge * GROW_RATIO))
    grown = selected.filter(ImageFilter.MaxFilter(2 * grow + 1))
    return grown.filter(ImageFilter.GaussianBlur(max(1.0, long_edge * FEATHER_RATIO)))


def compose(image_bytes: bytes, photo: Image.Image, selected: Image.Image, rotated: bool) -> bytes:
    """Check GPT's result, then keep it only inside the mask and the original photo everywhere else."""
    with Image.open(io.BytesIO(image_bytes)) as image:
        result = ImageOps.exif_transpose(image).convert("RGB")
    if rotated:
        result = result.rotate(90, expand=True)
    width, height = photo.size
    expected, actual = width / height, result.width / result.height
    if abs(actual - expected) / expected > ASPECT_TOLERANCE:
        raise BadResultError(
            f"GPT Image returned {result.width}x{result.height}, which does not match the photo {width}x{height}")
    if result.size != photo.size:
        result = result.resize(photo.size, Image.Resampling.LANCZOS)
    soft = blend_mask(selected)
    keep = ImageOps.invert(soft.point(lambda v: 255 if v > 0 else 0))
    if ImageStat.Stat(keep).mean[0] / 255 >= MIN_UNMASKED_SHARE:
        diff = alignment_diff(photo, result, keep)
        if diff > MAX_ALIGNMENT_DIFF:
            raise BadResultError(f"GPT Image moved or redrew the photo outside the mask (difference {diff:.1f})")
    return png_bytes(Image.composite(result, photo, soft))


def run_edit(photo_path: Path, mask: Image.Image, prompt: str, work_dir: Path) -> bytes:
    """Edit the masked area with GPT Image; retried on failure, a moderation rejection is raised immediately."""
    api_key = get_api_key()
    if not api_key:
        raise ValueError(f"GULU_GPTIMAGE_KEY is not set (environment or {GPU_TASK_CONFIG})")
    photo = load_upright(photo_path, work_dir)
    if max(photo.size) / min(photo.size) > GPT_MAX_ASPECT:
        raise ValueError(
            f"The image is {photo.width}x{photo.height}, whose aspect ratio is too extreme to edit "
            f"(the long edge may be at most {GPT_MAX_ASPECT:g} times the short edge)")
    target = output_size(photo.size)
    if target != photo.size:
        photo = photo.resize(target, Image.Resampling.LANCZOS)
    selected = selected_area(mask, photo.size)
    if not selected.getbbox():
        raise ValueError("The mask is empty. Paint the area you want to change and try again.")
    # GPT Image tends to reframe landscape images as portrait crops but keeps portrait ones aligned,
    # so a landscape photo and its mask are sent rotated 90 degrees and the result is rotated back.
    rotated = photo.width > photo.height
    sent_photo = photo.rotate(-90, expand=True) if rotated else photo
    sent_mask = selected.rotate(-90, expand=True) if rotated else selected
    photo_png = png_bytes(sent_photo)
    mask_png = png_bytes(sent_mask.convert("RGB"))
    size = request_size(sent_photo.size)
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            output = request_gpt_image(photo_png, mask_png, prompt, api_key, size)
            if not output:
                raise RuntimeError("GPT Image returned an empty image")
            return compose(output, photo, selected, rotated)
        except ModerationRejectedError:
            raise
        except Exception:
            if attempt == MAX_RETRIES:
                raise
            logger.warning("GPT Image attempt %d/%d failed; retrying", attempt, MAX_RETRIES, exc_info=True)
            time.sleep(RETRY_BACKOFF)
    raise AssertionError("unreachable")


def edit_and_save(photo_path: Path, mask: Image.Image, prompt: str) -> dict:
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        output = run_edit(photo_path, mask, prompt, output_dir)
    except ModerationRejectedError as error:
        raise ValueError(
            "The image model's content moderation rejected this image or description, so the area could not "
            "be edited. Try a different description or another image."
        ) from error
    if len(output) > MAX_BYTES:
        raise ValueError("The result exceeds 50 MB")
    output_path = output_dir / f"result-{uuid.uuid4().hex}.png"
    output_path.write_bytes(output)
    return {"outputs": [{"type": "image", "path": str(output_path)}]}


def main(task: dict) -> dict:
    """Use task.input.path as the photo, parameters.mask as the mask URL and parameters.prompt as the description
    (empty or missing: remove the painted object)."""
    parameters = task.get("parameters") or {}
    prompt = parameters.get("prompt")
    if prompt is not None and not isinstance(prompt, str):
        raise ValueError("The description must be text.")
    prompt = (prompt or "").strip() or DEFAULT_PROMPT
    if len(prompt) > MAX_PROMPT:
        raise ValueError(f"The description is too long (at most {MAX_PROMPT} characters).")
    inputs = task.get("input") or {}
    paths = inputs.get("imagePaths")
    if paths is not None and (not isinstance(paths, list) or len(paths) != 1):
        raise ValueError("Exactly one image is required.")
    path_value = inputs.get("path") or (paths[0] if paths else "")
    photo_path = Path(path_value) if isinstance(path_value, str) and path_value else None
    if photo_path is None or not photo_path.is_file():
        raise ValueError("task.input.path must point to an existing image")
    if photo_path.stat().st_size > MAX_BYTES:
        raise ValueError("Input image exceeds 50 MB")
    mask_url = parameters.get("mask")
    if not isinstance(mask_url, str) or not mask_url.strip():
        raise ValueError("A mask is required. Paint or upload the area you want to change.")
    return edit_and_save(photo_path, fetch_mask(mask_url.strip()), prompt)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Edit the masked area of a local image")
    parser.add_argument("image", type=Path)
    parser.add_argument("mask", type=Path, help="mask PNG: opaque white (or white on black) marks the area to change")
    parser.add_argument("--prompt", default="", help="what the painted area should become (default: remove the object)")
    arguments = parser.parse_args()
    with Image.open(arguments.mask) as mask_image:
        mask_image.load()
        print(json.dumps(edit_and_save(arguments.image, mask_image.copy(), arguments.prompt), ensure_ascii=False))
