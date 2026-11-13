"""Swap the outfit in a person photo with GPT Image (gpt-image-2.5-flare via guluapi) and return the image to Glance.

If GPT Image fails or rejects the images in content moderation, the task is retried on RunningHub.
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

import requests
from PIL import Image, ImageOps

import runninghub_fallback

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
MAX_RETRIES = 2  # RunningHub takes over afterwards; keep both within the task deadline
RETRY_BACKOFF = 5  # seconds between retries
MAX_BYTES = 50 * 1024 * 1024

# The result keeps the person photo's aspect ratio with its long edge clamped to this range.
MAX_LONG_EDGE = 2048
MIN_LONG_EDGE = 1024
GARMENT_MAX_EDGE = 1536  # the outfit reference only needs to be clear, not large
GPT_TARGET_PIXELS = 1024 * 1536
GPT_MAX_ASPECT = 3.0
ASPECT_TOLERANCE = 0.03

PROMPT = (
    "Image 1 is a photo of a person. Image 2 shows an outfit. "
    "Edit image 1 so that the person is wearing the outfit from image 2. "
    "Keep the person's face, hairstyle, skin tone, body shape, pose, hands, background and lighting "
    "exactly the same as image 1. Only change the clothing, matching the color, pattern, fabric, cut and "
    "details of the outfit in image 2. The result must be a natural, photorealistic photo with the same "
    "framing as image 1."
)

GPT_UPLOAD_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
MODERATION_CODES = {"moderation_blocked", "content_policy_violation", "content_filter", "safety_violation"}
MODERATION_KEYWORDS = ("moderation", "safety system", "content policy", "content_policy", "safety_violation",
                       "sensitive", "violat", "审核", "违规", "敏感")


class ModerationRejectedError(Exception):
    """GPT Image rejected the images in content moderation; retrying the same input will not help."""


class ReframedError(Exception):
    """GPT Image changed the framing, so its result cannot be mapped back to the person photo's size."""


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
    """Open an image as RGB with EXIF orientation applied; HEIC/HEIF is converted with sips first."""
    source = path
    if path.suffix.lower() not in GPT_UPLOAD_SUFFIXES:
        source = work_dir / f"converted-{uuid.uuid4().hex}.png"
        subprocess.run(["/usr/bin/sips", "-s", "format", "png", str(path), "--out", str(source)],
                       check=True, capture_output=True, timeout=60)
    with Image.open(source) as image:
        return ImageOps.exif_transpose(image).convert("RGB")


def save_png(image: Image.Image, work_dir: Path) -> Path:
    destination = work_dir / f"upload-{uuid.uuid4().hex}.png"
    image.save(destination, format="PNG")
    return destination


def prepare_uploads(person_path: Path, garment_path: Path, work_dir: Path):
    """Return (person upload, garment upload, target size, landscape).

    GPT Image tends to reframe landscape photos as portrait crops but keeps portrait
    photos aligned, so a landscape person photo is sent rotated 90 degrees and the
    result is rotated back.
    """
    person = load_upright(person_path, work_dir)
    target = output_size(person.size)
    width, height = target
    if max(width, height) / min(width, height) > GPT_MAX_ASPECT:
        raise ValueError(
            f"The person photo is {person.width}x{person.height}, whose aspect ratio is too extreme "
            f"(the long edge may be at most {GPT_MAX_ASPECT:g} times the short edge)")
    person = person.resize(target, Image.Resampling.LANCZOS) if target != person.size else person
    landscape = width > height
    person_upload = save_png(person.rotate(-90, expand=True) if landscape else person, work_dir)
    garment = load_upright(garment_path, work_dir)
    garment.thumbnail((GARMENT_MAX_EDGE, GARMENT_MAX_EDGE), Image.Resampling.LANCZOS)
    return person_upload, save_png(garment, work_dir), target, landscape


def request_gpt_image(person_upload: Path, garment_upload: Path, api_key: str, size: str) -> bytes:
    """Call the GPT Image edits endpoint with the person and outfit images and return the image bytes."""
    headers = {"Authorization": f"Bearer {api_key}", "User-Agent": USER_AGENT}
    data = {"model": MODEL, "prompt": PROMPT, "output_format": "png", "size": size, "n": "1"}
    logger.info("Submitting outfit swap to %s (%s, size=%s) ...", BASE_URL, MODEL, size)
    with person_upload.open("rb") as person, garment_upload.open("rb") as garment:
        response = requests.post(
            f"{BASE_URL}/v1/images/edits", headers=headers, data=data,
            files=[("image[]", (person_upload.name, person, "image/png")),
                   ("image[]", (garment_upload.name, garment, "image/png"))],
            timeout=REQUEST_TIMEOUT,
        )
    try:
        body = response.json()
    except ValueError:
        body = None
    if response.status_code != 200:
        if is_moderation_rejection(response.status_code, body):
            raise ModerationRejectedError(f"GPT Image moderation rejected the images: {body}")
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


def fit_to_target(image_bytes: bytes, target: tuple[int, int], landscape: bool) -> bytes:
    """Rotate a landscape result back and resize it to the person photo's output size; reject a changed framing."""
    with Image.open(io.BytesIO(image_bytes)) as image:
        result = ImageOps.exif_transpose(image).convert("RGB")
    if landscape:
        result = result.rotate(90, expand=True)
    width, height = target
    expected, actual = width / height, result.width / result.height
    if abs(actual - expected) / expected > ASPECT_TOLERANCE:
        raise ReframedError(
            f"GPT Image returned {result.width}x{result.height}, which does not match the photo's {width}x{height}")
    if result.size != target:
        result = result.resize(target, Image.Resampling.LANCZOS)
    buffer = io.BytesIO()
    result.save(buffer, format="PNG")
    return buffer.getvalue()


def run_gpt_image(person_path: Path, garment_path: Path, work_dir: Path) -> bytes:
    """Run GPT Image with retries; a moderation rejection is raised immediately."""
    api_key = get_api_key()
    if not api_key:
        raise ValueError(f"GULU_GPTIMAGE_KEY is not set (environment or {GPU_TASK_CONFIG})")
    person_upload, garment_upload, target, landscape = prepare_uploads(person_path, garment_path, work_dir)
    sent = (target[1], target[0]) if landscape else target
    size = request_size(sent)
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            output = request_gpt_image(person_upload, garment_upload, api_key, size)
            if not output:
                raise RuntimeError("GPT Image returned an empty image")
            return fit_to_target(output, target, landscape)
        except ModerationRejectedError:
            raise
        except Exception:
            if attempt == MAX_RETRIES:
                raise
            logger.warning("GPT Image attempt %d/%d failed; retrying", attempt, MAX_RETRIES, exc_info=True)
            time.sleep(RETRY_BACKOFF)
    raise AssertionError("unreachable")


def main(task: dict) -> dict:
    """Use the first image as the person and the second as the outfit."""
    paths = (task.get("input") or {}).get("imagePaths")
    if not isinstance(paths, list) or len(paths) != 2:
        raise ValueError("This Widget requires exactly two input images")
    images = [Path(value) for value in paths if isinstance(value, str) and value]
    if len(images) != 2 or any(not path.is_file() for path in images):
        raise ValueError("task.input.imagePaths must contain two existing images")
    if any(path.stat().st_size > MAX_BYTES for path in images):
        raise ValueError("Input image exceeds 50 MB")

    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        output = run_gpt_image(images[0], images[1], output_dir)
        if len(output) > MAX_BYTES:
            raise ValueError("The result exceeds 50 MB")
    except Exception as error:
        reason = "moderated" if isinstance(error, ModerationRejectedError) else "failed"
        logger.warning("GPT Image %s (%s); falling back to RunningHub", reason, error)
        return runninghub_fallback.run(task)
    output_path = output_dir / f"result-{uuid.uuid4().hex}.png"
    output_path.write_bytes(output)
    return {"outputs": [{"type": "image", "path": str(output_path)}]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run this Widget on a person photo and an outfit photo")
    parser.add_argument("person", type=Path)
    parser.add_argument("outfit", type=Path)
    arguments = parser.parse_args()
    print(json.dumps(main({"input": {"imagePaths": [str(arguments.person), str(arguments.outfit)]}}),
                     ensure_ascii=False))
