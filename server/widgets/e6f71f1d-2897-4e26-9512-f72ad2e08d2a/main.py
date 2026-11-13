"""Turn the selected image into a text-to-image prompt with GPT (gpt-5.6-luna via guluapi).

If the GPT request fails or returns no usable text, the task is retried on RunningHub.
"""

import base64
import io
import logging
import os
import time
from pathlib import Path

import requests
from PIL import Image, ImageOps

import runninghub_fallback

logger = logging.getLogger(__name__)

BASE_URL = "https://guluapi.com"
MODEL = "gpt-5.6-luna"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
# Same key source as gpu_task: env var first, then gpu_task/config/config.env.
GPU_TASK_CONFIG = Path(os.environ.get("GULU_CONFIG_ENV", Path.home() / "Desktop/work/gpu_task/config/config.env"))
REQUEST_TIMEOUT = 120
MAX_RETRIES = 2  # RunningHub takes over afterwards; keep both within the task deadline
RETRY_BACKOFF = 3
MAX_IMAGE_EDGE = 1536
MAX_TEXT_BYTES = 1024 * 1024

SYSTEM_PROMPT = (
    "You write prompts for text-to-image models. Look at the image and write one detailed prompt in English "
    "that would recreate it: subject and appearance, clothing, pose and expression, setting and background, "
    "composition and camera angle, lighting, color palette, style and mood. Output only the prompt as a single "
    "paragraph, with no preface, labels or markdown."
)


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


def image_data_url(image_path: Path) -> str:
    """Encode the image as an upright JPEG data URL no larger than MAX_IMAGE_EDGE."""
    with Image.open(image_path) as image:
        upright = ImageOps.exif_transpose(image).convert("RGB")
    upright.thumbnail((MAX_IMAGE_EDGE, MAX_IMAGE_EDGE), Image.Resampling.LANCZOS)
    buffer = io.BytesIO()
    upright.save(buffer, format="JPEG", quality=85)
    return "data:image/jpeg;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")


def request_prompt(data_url: str, api_key: str) -> str:
    """Ask the vision model for a prompt and return its text."""
    logger.info("Requesting an image prompt from %s (%s) ...", BASE_URL, MODEL)
    response = requests.post(
        f"{BASE_URL}/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}", "User-Agent": USER_AGENT},
        json={"model": MODEL, "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": [{"type": "image_url", "image_url": {"url": data_url}}]},
        ]},
        timeout=REQUEST_TIMEOUT,
    )
    if response.status_code != 200:
        raise RuntimeError(f"GPT error: {response.status_code}, {response.text[:500]}")
    try:
        choice = response.json()["choices"][0]
        text = (choice["message"].get("content") or "").strip()
    except (ValueError, KeyError, IndexError, TypeError, AttributeError) as error:
        raise RuntimeError(f"GPT returned an unexpected response: {response.text[:500]}") from error
    if not text:
        raise RuntimeError(f"GPT returned no text (finish_reason={choice.get('finish_reason')})")
    if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
        raise ValueError("GPT text result exceeds 1 MB")
    return text


def run_gpt(image_path: Path) -> str:
    api_key = get_api_key()
    if not api_key:
        raise ValueError(f"GULU_GPTIMAGE_KEY is not set (environment or {GPU_TASK_CONFIG})")
    data_url = image_data_url(image_path)
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return request_prompt(data_url, api_key)
        except Exception:
            if attempt == MAX_RETRIES:
                raise
            logger.warning("GPT attempt %d/%d failed; retrying", attempt, MAX_RETRIES, exc_info=True)
            time.sleep(RETRY_BACKOFF)
    raise AssertionError("unreachable")


def main(task: dict) -> dict:
    image_value = (task.get("input") or {}).get("path")
    image_path = Path(image_value) if image_value else None
    if image_path is None or not image_path.is_file():
        raise ValueError("task.input.path must point to an existing image")
    try:
        text = run_gpt(image_path)
    except Exception as error:
        logger.warning("GPT failed (%s); falling back to RunningHub", error)
        return runninghub_fallback.run(task)
    return {"outputs": [{"type": "text", "text": text}]}
