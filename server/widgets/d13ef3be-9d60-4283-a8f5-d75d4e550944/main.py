"""Expand one image with GPT Image (gpt-image-2.5-flare via guluapi) and return the result to Glance.

The photo is placed in the middle of a larger transparent canvas, GPT Image fills the surrounding
area, and the original pixels are pasted back so the original picture is never redrawn. If GPT
Image fails or rejects the image in content moderation, the task is retried on RunningHub.
"""

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

import requests
from PIL import Image, ImageChops, ImageFilter, ImageOps, ImageStat

import runninghub_fallback

logger = logging.getLogger(__name__)

BASE_URL = "https://guluapi.com"
MODEL = "gpt-image-2.5-flare"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
# Same key source as gpu_task: env var first, then gpu_task/config/config.env.
GPU_TASK_CONFIG = Path(os.environ.get("GULU_CONFIG_ENV", Path.home() / "Desktop/work/gpu_task/config/config.env"))
REQUEST_TIMEOUT = 300
MAX_RETRIES = 2  # RunningHub takes over afterwards; keep both within the task deadline
RETRY_BACKOFF = 5
MAX_BYTES = 50 * 1024 * 1024

EXPAND_FACTOR = 1.5  # the canvas is 1.5x the photo in each direction (25% added on every side)
MAX_LONG_EDGE = 2048
MIN_LONG_EDGE = 1024
GPT_TARGET_PIXELS = 1024 * 1536
GPT_MAX_ASPECT = 3.0
ASPECT_TOLERANCE = 0.03
# Mean per-pixel difference (0-255) between GPT's middle region and the original photo; a result that
# kept the photo in place scores low, a reframed or shifted one scores high.
MAX_ALIGNMENT_DIFF = 35
FEATHER_RATIO = 0.05  # blend width of the seam, relative to the canvas long edge

PROMPT = (
    "The image shows a photo in the middle, surrounded by an empty transparent area. Extend the scene "
    "naturally outward into the transparent area on all four sides, continuing the same scene, perspective, "
    "lighting, colors, style and level of detail. Keep the existing photo in the middle exactly as it is: "
    "do not crop, zoom, move or redraw it. Output the complete image with no transparent areas, borders "
    "or frames."
)

GPT_UPLOAD_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
MODERATION_CODES = {"moderation_blocked", "content_policy_violation", "content_filter", "safety_violation"}
MODERATION_KEYWORDS = ("moderation", "safety system", "content policy", "content_policy", "safety_violation",
                       "sensitive", "violat", "审核", "违规", "敏感")


class ModerationRejectedError(Exception):
    """GPT Image rejected the image in content moderation; retrying the same input will not help."""


class BadResultError(Exception):
    """GPT Image returned a result that cannot be used (reframed, shifted or not filled in)."""


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


def layout(photo_size: tuple[int, int]):
    """Return (canvas size, photo box) for the expanded canvas; the photo is centered."""
    width, height = photo_size
    canvas = output_size((round(width * EXPAND_FACTOR), round(height * EXPAND_FACTOR)))
    photo_w, photo_h = round(canvas[0] / EXPAND_FACTOR), round(canvas[1] / EXPAND_FACTOR)
    left, top = (canvas[0] - photo_w) // 2, (canvas[1] - photo_h) // 2
    return canvas, (left, top, left + photo_w, top + photo_h)


def prepare_canvas(photo: Image.Image):
    """Return (transparent canvas with the photo in the middle, canvas size, photo box, resized photo)."""
    canvas_size, box = layout(photo.size)
    resized = photo.resize((box[2] - box[0], box[3] - box[1]), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    canvas.paste(resized.convert("RGBA"), (box[0], box[1]))
    return canvas, canvas_size, box, resized


def request_gpt_image(canvas_path: Path, api_key: str, size: str) -> bytes:
    """Call the GPT Image edits endpoint and return the image bytes."""
    headers = {"Authorization": f"Bearer {api_key}", "User-Agent": USER_AGENT}
    data = {"model": MODEL, "prompt": PROMPT, "output_format": "png", "size": size, "n": "1"}
    logger.info("Submitting outpainting to %s (%s, size=%s) ...", BASE_URL, MODEL, size)
    with canvas_path.open("rb") as stream:
        response = requests.post(
            f"{BASE_URL}/v1/images/edits", headers=headers, data=data,
            files={"image[]": (canvas_path.name, stream, "image/png")}, timeout=REQUEST_TIMEOUT,
        )
    try:
        body = response.json()
    except ValueError:
        body = None
    if response.status_code != 200:
        if is_moderation_rejection(response.status_code, body):
            raise ModerationRejectedError(f"GPT Image moderation rejected the image: {body}")
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


def alignment_diff(original: Image.Image, result: Image.Image) -> float:
    """Mean difference between the original photo and GPT's middle region, at a small scale."""
    small = (256, max(1, round(256 * original.height / original.width)))
    difference = ImageChops.difference(original.convert("RGB").resize(small), result.convert("RGB").resize(small))
    return ImageStat.Stat(difference.convert("L")).mean[0]


def compose(image_bytes: bytes, canvas_size: tuple[int, int], box: tuple[int, int, int, int],
            photo: Image.Image, rotated: bool) -> bytes:
    """Turn GPT's result into the final image: check it, then paste the original photo back with a soft seam."""
    with Image.open(io.BytesIO(image_bytes)) as image:
        result = ImageOps.exif_transpose(image).convert("RGBA")
    if rotated:
        result = result.rotate(90, expand=True)
    width, height = canvas_size
    expected, actual = width / height, result.width / result.height
    if abs(actual - expected) / expected > ASPECT_TOLERANCE:
        raise BadResultError(
            f"GPT Image returned {result.width}x{result.height}, which does not match the canvas {width}x{height}")
    if result.size != canvas_size:
        result = result.resize(canvas_size, Image.Resampling.LANCZOS)
    corners = [result.getpixel(point)[3] for point in (
        (0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1),
        (width // 2, 0), (width // 2, height - 1), (0, height // 2), (width - 1, height // 2))]
    if min(corners) < 250:
        raise BadResultError("GPT Image left the expanded area transparent")
    diff = alignment_diff(photo, result.crop(box))
    if diff > MAX_ALIGNMENT_DIFF:
        raise BadResultError(f"GPT Image moved or redrew the original photo (difference {diff:.1f})")
    # Paste the original back; fade the mask in at the seam so generated and original pixels blend.
    # The fade lies inside the photo's edge band, where GPT's own version of the photo is nearly identical,
    # so small tone differences between the original and the generated area disappear instead of showing as a line.
    feather = max(2, round(max(canvas_size) * FEATHER_RATIO))
    mask = Image.new("L", canvas_size, 0)
    mask.paste(255, (box[0] + feather, box[1] + feather, box[2] - feather, box[3] - feather))
    mask = mask.filter(ImageFilter.GaussianBlur(feather / 2.5))
    final = result.convert("RGB")
    original_layer = Image.new("RGB", canvas_size)
    original_layer.paste(photo, (box[0], box[1]))
    final = Image.composite(original_layer, final, mask)
    buffer = io.BytesIO()
    final.save(buffer, format="PNG")
    return buffer.getvalue()


def run_gpt_image(input_path: Path, work_dir: Path) -> bytes:
    """Run GPT Image with retries and return the expanded PNG; a moderation rejection is raised immediately."""
    api_key = get_api_key()
    if not api_key:
        raise ValueError(f"GULU_GPTIMAGE_KEY is not set (environment or {GPU_TASK_CONFIG})")
    photo = load_upright(input_path, work_dir)
    if max(photo.size) / min(photo.size) > GPT_MAX_ASPECT:
        raise ValueError(
            f"The image is {photo.width}x{photo.height}, whose aspect ratio is too extreme to expand "
            f"(the long edge may be at most {GPT_MAX_ASPECT:g} times the short edge)")
    canvas, canvas_size, box, resized = prepare_canvas(photo)
    # GPT Image tends to reframe landscape images as portrait crops but keeps portrait ones aligned,
    # so a landscape canvas is sent rotated 90 degrees and the result is rotated back.
    rotated = canvas_size[0] > canvas_size[1]
    sent = canvas.rotate(-90, expand=True) if rotated else canvas
    canvas_path = work_dir / f"canvas-{uuid.uuid4().hex}.png"
    sent.save(canvas_path, format="PNG")
    size = request_size(sent.size)
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            output = request_gpt_image(canvas_path, api_key, size)
            if not output:
                raise RuntimeError("GPT Image returned an empty image")
            return compose(output, canvas_size, box, resized, rotated)
        except ModerationRejectedError:
            raise
        except Exception:
            if attempt == MAX_RETRIES:
                raise
            logger.warning("GPT Image attempt %d/%d failed; retrying", attempt, MAX_RETRIES, exc_info=True)
            time.sleep(RETRY_BACKOFF)
    raise AssertionError("unreachable")


def main(task: dict) -> dict:
    """Use the selected Glance image; try GPT Image first and fall back to RunningHub."""
    input_path = (task.get("input") or {}).get("path")
    if not isinstance(input_path, str) or not input_path or not Path(input_path).is_file():
        raise ValueError("task.input.path must point to one existing image")
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        output = run_gpt_image(Path(input_path), output_dir)
        if len(output) > MAX_BYTES:
            raise ValueError("The result exceeds 50 MB")
    except Exception as error:
        reason = "moderated" if isinstance(error, ModerationRejectedError) else "failed"
        logger.warning("GPT Image %s (%s); falling back to RunningHub", reason, error)
        return runninghub_fallback.run(task)
    output_path = output_dir / f"result-{uuid.uuid4().hex}.png"
    output_path.write_bytes(output)
    return {"outputs": [{"type": "image", "path": str(output_path)}]}
