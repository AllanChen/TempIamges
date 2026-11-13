"""Remove an image background with GPT Image (gpt-image-2 via guluapi) and return a local image to Glance.

If GPT Image rejects the image in content moderation, fall back to
on-device Apple Vision segmentation (remove_bg_vision.swift).
"""

import argparse
import base64
import hashlib
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
from PIL import Image, ImageChops, ImageOps, ImageStat

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

WIDGET_DIR = Path(__file__).resolve().parent
VISION_SCRIPT = WIDGET_DIR / "remove_bg_vision.swift"

BASE_URL = "https://guluapi.com"
MODEL = "gpt-image-2.5-flare"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
# Same key source as gpu_task: env var first, then gpu_task/config/config.env.
GPU_TASK_CONFIG = Path(os.environ.get("GULU_CONFIG_ENV", Path.home() / "Desktop/work/gpu_task/config/config.env"))
REQUEST_TIMEOUT = 300

MAX_RETRIES = 3
RETRY_BACKOFF = 5  # seconds between retries
MAX_BYTES = 50 * 1024 * 1024
# Output keeps the original aspect ratio with its long edge clamped to this range.
MAX_LONG_EDGE = 2048
MIN_LONG_EDGE = 1024

PROMPT = (
    "Remove the background completely and output the main subject on a fully transparent background. "
    "Keep the subject exactly as it is: same pose, shape, colors, details and fine edges such as hair. "
    "Do not add, remove or redraw anything on the subject."
)

GPT_UPLOAD_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
GPT_TARGET_PIXELS = 1024 * 1536  # request size budget; the result is resized back to the original size
GPT_MAX_ASPECT = 3.0
ASPECT_TOLERANCE = 0.03
# Mean per-pixel difference (0-255) between GPT's subject and the original; aligned results score ~12,
# reframed ones ~90.
MAX_ALIGNMENT_DIFF = 35
MODERATION_CODES = {"moderation_blocked", "content_policy_violation", "content_filter", "safety_violation"}
MODERATION_KEYWORDS = ("moderation", "safety system", "content policy", "content_policy", "safety_violation",
                       "sensitive", "violat", "审核", "违规", "敏感")


class ModerationRejectedError(Exception):
    """The GPT Image service rejected the image in content moderation.

    Retrying the same input will always be rejected, so we switch to the
    on-device Vision fallback instead.
    """


class NotTransparentError(Exception):
    """GPT Image returned an image without a transparent background."""


class ReframedError(Exception):
    """GPT Image changed the framing, so its result cannot be mapped back to the original size."""


class VisionNoSubjectError(Exception):
    """Apple Vision could not find a foreground subject in the image."""


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


def resize_to_output(path: Path) -> None:
    """Resize a result PNG in place to the output size limits."""
    with Image.open(path) as image:
        target = output_size(image.size)
        if target == image.size:
            return
        resized = image.convert("RGBA").resize(target, Image.Resampling.LANCZOS)
    resized.save(path, format="PNG")


def prepare_upload(input_path: Path, work_dir: Path) -> tuple[Path, tuple[int, int]]:
    """Write an upright PNG at the output size for GPT Image and return it with that size.

    GPT Image accepts PNG/JPEG/WebP only, so HEIC/HEIF is converted with sips first.
    EXIF orientation is applied so GPT sees the same image the user sees.
    """
    source = input_path
    if input_path.suffix.lower() not in GPT_UPLOAD_SUFFIXES:
        source = work_dir / f"converted-{uuid.uuid4().hex}.png"
        subprocess.run(
            ["/usr/bin/sips", "-s", "format", "png", str(input_path), "--out", str(source)],
            check=True, capture_output=True, timeout=60,
        )
    upload = work_dir / f"upload-{uuid.uuid4().hex}.png"
    with Image.open(source) as image:
        upright = ImageOps.exif_transpose(image)
        target = output_size(upright.size)
        if target != upright.size:
            upright = upright.resize(target, Image.Resampling.LANCZOS)
        upright.save(upload, format="PNG")
        return upload, target


def request_size(size: tuple[int, int]) -> str:
    """Pick a GPT output size with the original aspect ratio (multiples of 16)."""
    width, height = size
    scale = (GPT_TARGET_PIXELS / (width * height)) ** 0.5
    return f"{max(16, round(width * scale / 16) * 16)}x{max(16, round(height * scale / 16) * 16)}"


def alignment_diff(original: Image.Image, result: Image.Image) -> float:
    """Mean difference between the original and GPT's opaque subject pixels, at a small scale."""
    small = (256, max(1, round(256 * original.height / original.width)))
    original_small = original.convert("RGB").resize(small)
    result_small = result.resize(small)
    subject = result_small.getchannel("A").point(lambda alpha: 255 if alpha > 200 else 0)
    if not subject.getbbox():
        return float("inf")
    difference = ImageChops.difference(original_small, result_small.convert("RGB")).convert("L")
    return ImageStat.Stat(difference, subject).mean[0]


def fit_to_original(image_bytes: bytes, upload_path: Path) -> bytes:
    """Resize the GPT result to the upload's size (the output size); reject a changed framing.

    GPT Image regenerates the picture and may reframe it (e.g. turn a landscape
    photo into a portrait crop), so check both aspect ratio and pixel alignment.
    """
    with Image.open(io.BytesIO(image_bytes)) as image:
        result = image.convert("RGBA")
    with Image.open(upload_path) as image:
        original = image.convert("RGB")
    width, height = original.size
    expected, actual = width / height, result.width / result.height
    if abs(actual - expected) / expected > ASPECT_TOLERANCE:
        raise ReframedError(
            f"GPT Image returned {result.width}x{result.height}, which does not match the original {width}x{height}")
    if result.size != original.size:
        result = result.resize(original.size, Image.Resampling.LANCZOS)
    diff = alignment_diff(original, result)
    if diff > MAX_ALIGNMENT_DIFF:
        raise ReframedError(f"GPT Image result is not aligned with the original (difference {diff:.1f})")
    buffer = io.BytesIO()
    result.save(buffer, format="PNG")
    return buffer.getvalue()


def request_gpt_image(upload_path: Path, api_key: str, size: str) -> bytes:
    """Call the GPT Image edits endpoint and return the image bytes."""
    headers = {"Authorization": f"Bearer {api_key}", "User-Agent": USER_AGENT}
    data = {
        "model": MODEL,
        "prompt": PROMPT,
        "background": "transparent",
        "output_format": "png",
        "size": size,
        "n": "1",
    }

    logger.info("Submitting background removal to %s (%s, size=%s) ...", BASE_URL, MODEL, size)
    with upload_path.open("rb") as stream:
        response = requests.post(
            f"{BASE_URL}/v1/images/edits", headers=headers, data=data,
            files={"image[]": (upload_path.name, stream, "image/png")}, timeout=REQUEST_TIMEOUT,
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


def has_transparency(image_bytes: bytes) -> bool:
    """A valid background-removal result must contain transparent pixels."""
    with Image.open(io.BytesIO(image_bytes)) as image:
        if image.mode not in ("RGBA", "LA", "PA") and "transparency" not in image.info:
            return False
        alpha = image.convert("RGBA").getchannel("A")
        low, _ = alpha.getextrema()
        return low < 255


def rotate_png(source: Path | bytes, degrees: int, destination: Path | None = None) -> bytes:
    """Rotate a PNG by `degrees` counter-clockwise (expanding the canvas); write it too if asked."""
    with Image.open(io.BytesIO(source) if isinstance(source, bytes) else source) as image:
        rotated = image.convert("RGBA").rotate(degrees, expand=True)
    buffer = io.BytesIO()
    rotated.save(buffer, format="PNG")
    if destination:
        destination.write_bytes(buffer.getvalue())
    return buffer.getvalue()


def run_gpt_image(input_path: Path, work_dir: Path) -> bytes:
    """Run GPT Image with retries and return a PNG at the original size.

    Only a moderation rejection is raised immediately so the caller can fall back
    to Vision; every other failure (including a result without transparency or with
    changed framing) is retried and then fails the task.
    """
    api_key = get_api_key()
    if not api_key:
        raise ValueError(f"GULU_GPTIMAGE_KEY is not set (environment or {GPU_TASK_CONFIG})")
    upload_path, original_size = prepare_upload(input_path, work_dir)
    width, height = original_size
    if max(width, height) / min(width, height) > GPT_MAX_ASPECT:
        raise ValueError(
            f"The image is {width}x{height}, whose aspect ratio is too extreme for background removal "
            f"(the long edge may be at most {GPT_MAX_ASPECT:g} times the short edge)")
    # GPT Image tends to reframe landscape images as portrait crops but keeps portrait
    # images aligned, so send landscape images rotated 90 degrees and rotate the result back.
    landscape = width > height
    gpt_input = upload_path
    if landscape:
        gpt_input = work_dir / f"rotated-{uuid.uuid4().hex}.png"
        rotate_png(upload_path, -90, gpt_input)
    size = request_size((height, width) if landscape else original_size)
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            output = request_gpt_image(gpt_input, api_key, size)
            if not output:
                raise RuntimeError("GPT Image returned an empty image")
            if not has_transparency(output):
                raise NotTransparentError("GPT Image result has no transparent background")
            if landscape:
                output = rotate_png(output, 90)
            return fit_to_original(output, upload_path)
        except ModerationRejectedError:
            raise
        except Exception:
            if attempt == MAX_RETRIES:
                raise
            logger.warning("GPT Image attempt %d/%d failed; retrying", attempt, MAX_RETRIES, exc_info=True)
            time.sleep(RETRY_BACKOFF)
    raise AssertionError("unreachable")


def vision_binary() -> list[str]:
    """Compile the Vision helper once into a cache; fall back to the Swift interpreter."""
    digest = hashlib.sha256(VISION_SCRIPT.read_bytes()).hexdigest()[:16]
    cache_dir = Path.home() / "Library" / "Caches" / "glance-widgets" / "remove-bg-vision"
    binary = cache_dir / f"remove_bg_vision-{digest}"
    if binary.is_file():
        return [str(binary)]
    cache_dir.mkdir(parents=True, exist_ok=True)
    staging = cache_dir / f".build-{uuid.uuid4().hex}"
    try:
        subprocess.run(
            ["/usr/bin/swiftc", "-O", str(VISION_SCRIPT), "-o", str(staging)],
            check=True, capture_output=True, timeout=300,
        )
        os.replace(staging, binary)
        return [str(binary)]
    except (OSError, subprocess.SubprocessError):
        logger.warning("Could not compile the Vision helper; using the Swift interpreter", exc_info=True)
        staging.unlink(missing_ok=True)
        return ["/usr/bin/swift", str(VISION_SCRIPT)]


def run_vision(input_path: Path, output_path: Path) -> None:
    """Remove the background on-device with Apple Vision."""
    logger.info("Running on-device Apple Vision background removal ...")
    result = subprocess.run(
        [*vision_binary(), str(input_path), str(output_path)],
        capture_output=True, text=True, timeout=300,
    )
    if result.stdout.strip():
        logger.info(result.stdout.strip())
    if result.returncode == 3:
        raise VisionNoSubjectError(
            "No clear foreground subject was found in this image, so the background could not be removed. "
            "Try an image with a distinct main subject."
        )
    if result.returncode != 0:
        raise RuntimeError(f"Apple Vision background removal failed: {result.stderr.strip() or result.returncode}")
    if not output_path.is_file() or output_path.stat().st_size == 0:
        raise RuntimeError("Apple Vision returned an empty image")


def main(task: dict) -> dict:
    """Process the image already downloaded by glance worker."""
    input_path = Path((task.get("input") or {}).get("path", ""))
    if not input_path.is_file():
        raise ValueError("task.input.path must point to an existing image")
    if input_path.stat().st_size > MAX_BYTES:
        raise ValueError("Input image exceeds 50 MB")
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"result-{uuid.uuid4().hex}.png"

    try:
        output = run_gpt_image(input_path, output_dir)
        if len(output) > MAX_BYTES:
            raise ValueError("GPT Image result exceeds 50 MB")
        output_path.write_bytes(output)
    except ModerationRejectedError as error:
        logger.warning("%s; falling back to Apple Vision", error)
        run_vision(input_path, output_path)
        resize_to_output(output_path)

    if output_path.stat().st_size > MAX_BYTES:
        raise ValueError("Background removal result exceeds 50 MB")
    return {"outputs": [{"type": "image", "path": str(output_path)}]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run this Widget on a local image")
    parser.add_argument("image", type=Path)
    arguments = parser.parse_args()
    print(json.dumps(main({"input": {"path": str(arguments.image)}}), ensure_ascii=False))
