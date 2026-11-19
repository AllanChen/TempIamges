"""Translate or replace the text in an image with GPT Image (gpt-image-2.5-flare via guluapi).

Inputs: the image (task.input.path) and a text instruction (parameters.prompt) such as
"把英文改成中文" or "change the text from English to Chinese". GPT Image redraws the picture with
the text translated or replaced, keeping the layout and style of the original.
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

# The result keeps the original aspect ratio with its long edge clamped to this range.
MAX_LONG_EDGE = 2048
MIN_LONG_EDGE = 1024
GPT_TARGET_PIXELS = 1024 * 1536
GPT_MAX_ASPECT = 3.0

PROMPT = (
    "Edit this image by changing its visible text as follows: {prompt}\n"
    "Translate or replace every affected text element, and redraw each translated text in place so it "
    "matches the original font style, size, weight, color, alignment and orientation as closely as "
    "possible, fitting the translated text within the same area. Keep everything else — the background, "
    "graphics, layout, lighting, texture and framing — exactly the same. Do not add, remove or move any "
    "other element. Output only the edited image."
)

DEFAULT_PROMPT = "Translate all English text in this image into Simplified Chinese."

GPT_UPLOAD_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
MODERATION_CODES = {"moderation_blocked", "content_policy_violation", "content_filter", "safety_violation"}
MODERATION_KEYWORDS = ("moderation", "safety system", "content policy", "content_policy", "safety_violation",
                       "sensitive", "violat", "审核", "违规", "敏感")


class ModerationRejectedError(Exception):
    """GPT Image rejected the image or prompt in content moderation; retrying will not help."""


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


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def request_gpt_image(photo_png: bytes, prompt: str, api_key: str, size: str) -> bytes:
    """Call the GPT Image edits endpoint with the photo and return the edited image bytes."""
    headers = {"Authorization": f"Bearer {api_key}", "User-Agent": USER_AGENT}
    data = {"model": MODEL, "prompt": prompt, "output_format": "png", "size": size, "n": "1"}
    logger.info("Submitting text translation edit to %s (%s, size=%s) ...", BASE_URL, MODEL, size)
    response = requests.post(
        f"{BASE_URL}/v1/images/edits", headers=headers, data=data,
        files=[("image[]", ("photo.png", photo_png, "image/png"))],
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


def run_edit(photo_path: Path, prompt: str, work_dir: Path) -> bytes:
    """Translate the image's text with GPT Image; retried on failure, moderation rejection raises at once."""
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
    photo_png = png_bytes(photo)
    size = request_size(photo.size)
    full_prompt = PROMPT.format(prompt=prompt)
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            output = request_gpt_image(photo_png, full_prompt, api_key, size)
            if not output:
                raise RuntimeError("GPT Image returned an empty image")
            return output
        except ModerationRejectedError:
            raise
        except Exception:
            if attempt == MAX_RETRIES:
                raise
            logger.warning("GPT Image attempt %d/%d failed; retrying", attempt, MAX_RETRIES, exc_info=True)
            time.sleep(RETRY_BACKOFF)
    raise AssertionError("unreachable")


def edit_and_save(photo_path: Path, prompt: str) -> dict:
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        output = run_edit(photo_path, prompt, output_dir)
    except ModerationRejectedError as error:
        raise ValueError(
            "The image model's content moderation rejected this image or instruction, so the text could "
            "not be translated. Try a different instruction or another image."
        ) from error
    if len(output) > MAX_BYTES:
        raise ValueError("The result exceeds 50 MB")
    output_path = output_dir / f"result-{uuid.uuid4().hex}.png"
    output_path.write_bytes(output)
    return {"outputs": [{"type": "image", "path": str(output_path)}]}


def main(task: dict) -> dict:
    """Use task.input.path as the image and parameters.prompt as the translation instruction
    (empty or missing: translate English text into Simplified Chinese)."""
    parameters = task.get("parameters") or {}
    prompt = parameters.get("prompt")
    if prompt is not None and not isinstance(prompt, str):
        raise ValueError("The instruction must be text.")
    prompt = (prompt or "").strip() or DEFAULT_PROMPT
    if len(prompt) > MAX_PROMPT:
        raise ValueError(f"The instruction is too long (at most {MAX_PROMPT} characters).")
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
    return edit_and_save(photo_path, prompt)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Translate or replace the text of a local image")
    parser.add_argument("image", type=Path)
    parser.add_argument("--prompt", default="",
                        help="what to do with the text (default: translate English text into Chinese)")
    arguments = parser.parse_args()
    print(json.dumps(edit_and_save(arguments.image, arguments.prompt), ensure_ascii=False))
