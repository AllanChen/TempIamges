"""Generate an image with the configured RunningHub AI app."""

import json
import os
from pathlib import Path
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import uuid


RUNNINGHUB_APP_ID = "2019311392569954306"
RUN_URL = f"https://www.runninghub.cn/openapi/v2/run/ai-app/{RUNNINGHUB_APP_ID}"
QUERY_URL = "https://www.runninghub.cn/openapi/v2/query"
POLL_INTERVAL = 5
POLL_TIMEOUT = 20 * 60
MAX_OUTPUT_BYTES = 50 * 1024 * 1024

PROMPT_INSTRUCTIONS = (
    "扮演一个生图提示词生成专家，理解用户的prompt 然后生成对应的生图提示词。"
    "提示词直接输出英文输出生图提示词就可以，不用解析。"
)
IMAGE_PROMPT = "一个欧美女生，自拍，背景可以是任何地方，服装正常。"


def api_key() -> str:
    """Read the secret from the Worker environment; never print it."""
    value = os.environ.get("RUNNINGHUB_API_KEY", "").strip()
    if not value:
        raise ValueError("RUNNINGHUB_API_KEY is required in the Worker environment")
    return value


def redact(value: object, key: str) -> str:
    return str(value).replace(key, "[REDACTED]")[:1000]


def image_dimensions(path: Path) -> tuple[int, int]:
    """Read PNG, JPEG, or WebP dimensions without third-party packages."""
    with path.open("rb") as image:
        header = image.read(24)
        if header.startswith(b"\x89PNG\r\n\x1a\n") and len(header) >= 24:
            return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")

        if header.startswith(b"\xff\xd8"):
            image.seek(2)
            start_of_frame = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                              0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
            while True:
                byte = image.read(1)
                if not byte:
                    break
                if byte != b"\xff":
                    continue
                marker_byte = image.read(1)
                while marker_byte == b"\xff":
                    marker_byte = image.read(1)
                if not marker_byte:
                    break
                marker = marker_byte[0]
                if marker in {0xD8, 0xD9, 0x01, *range(0xD0, 0xD8)}:
                    continue
                length_bytes = image.read(2)
                if len(length_bytes) != 2:
                    break
                segment_length = int.from_bytes(length_bytes, "big")
                if segment_length < 2:
                    break
                if marker in start_of_frame:
                    frame = image.read(5)
                    if len(frame) == 5:
                        height = int.from_bytes(frame[1:3], "big")
                        width = int.from_bytes(frame[3:5], "big")
                        if width and height:
                            return width, height
                    break
                image.seek(segment_length - 2, 1)
            raise ValueError("Could not read dimensions from JPEG input")

        if header.startswith(b"RIFF") and header[8:12] == b"WEBP":
            image.seek(12)
            while True:
                chunk_header = image.read(8)
                if len(chunk_header) != 8:
                    break
                chunk_type = chunk_header[:4]
                chunk_size = int.from_bytes(chunk_header[4:8], "little")
                data = image.read(min(chunk_size, 30))
                if chunk_type == b"VP8X" and len(data) >= 10:
                    width = 1 + int.from_bytes(data[4:7], "little")
                    height = 1 + int.from_bytes(data[7:10], "little")
                    return width, height
                if chunk_type == b"VP8L" and len(data) >= 5 and data[0] == 0x2F:
                    width = 1 + (((data[2] & 0x3F) << 8) | data[1])
                    height = 1 + (((data[4] & 0x0F) << 10) | (data[3] << 2) | ((data[2] & 0xC0) >> 6))
                    return width, height
                if chunk_type == b"VP8 " and len(data) >= 10 and data[3:6] == b"\x9d\x01\x2a":
                    width = int.from_bytes(data[6:8], "little") & 0x3FFF
                    height = int.from_bytes(data[8:10], "little") & 0x3FFF
                    if width and height:
                        return width, height
                image.seek(max(0, chunk_size - len(data)) + (chunk_size & 1), 1)
            raise ValueError("Could not read dimensions from WebP input")

    raise ValueError("Input must be a PNG, JPEG, or WebP image")


def post_json(url: str, payload: dict, key: str, operation: str) -> dict:
    request = Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {key}",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=60) as response:
            result = json.load(response)
    except HTTPError as error:
        detail = error.read(4096).decode("utf-8", errors="replace")
        raise RuntimeError(
            f"RunningHub {operation} failed: HTTP {error.code}: {redact(detail, key)}"
        ) from error
    if not isinstance(result, dict):
        raise RuntimeError(f"RunningHub {operation} returned an invalid response")
    return result


def submit(key: str, width: int, height: int) -> str:
    payload = {
        "nodeInfoList": [
            {"nodeId": "13", "fieldName": "height", "fieldValue": str(height), "description": "height"},
            {"nodeId": "13", "fieldName": "width", "fieldValue": str(width), "description": "width"},
            {"nodeId": "20", "fieldName": "text", "fieldValue": PROMPT_INSTRUCTIONS, "description": "text"},
            {"nodeId": "21", "fieldName": "text", "fieldValue": IMAGE_PROMPT, "description": "text"},
        ],
        "instanceType": "default",
        "usePersonalQueue": "false",
    }
    result = post_json(RUN_URL, payload, key, "submit")
    task_id = result.get("taskId")
    if not isinstance(task_id, str) or not task_id:
        raise RuntimeError(f"RunningHub submit returned no taskId: {redact(result, key)}")
    print(f"RunningHub task submitted: {task_id}")
    return task_id


def poll_result_url(key: str, task_id: str) -> str:
    started = time.monotonic()
    while time.monotonic() - started < POLL_TIMEOUT:
        result = post_json(QUERY_URL, {"taskId": task_id}, key, "query")
        status = result.get("status")
        print(f"RunningHub task {task_id}: {status}")
        if status == "SUCCESS":
            results = result.get("results") or []
            output_url = results[0].get("url") if results and isinstance(results[0], dict) else None
            parsed = urlparse(output_url or "")
            if parsed.scheme != "https" or not parsed.hostname:
                raise RuntimeError("RunningHub completed without a valid HTTPS image URL")
            return output_url
        if status in ("QUEUED", "RUNNING"):
            time.sleep(POLL_INTERVAL)
            continue
        message = redact(result.get("errorMessage", "Unknown error"), key)
        raise RuntimeError(f"RunningHub task failed: {message} (status={status})")
    raise TimeoutError(f"RunningHub task {task_id} timed out after {POLL_TIMEOUT} seconds")


def download_image(url: str, output_dir: Path) -> Path:
    request = Request(url, headers={"User-Agent": "Glance-Widget/1.0"})
    with urlopen(request, timeout=60) as response:
        mime = response.headers.get_content_type()
        suffix = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}.get(mime, ".png")
        destination = output_dir / f"runninghub-{uuid.uuid4().hex}{suffix}"
        total = 0
        with destination.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_OUTPUT_BYTES:
                    raise ValueError("RunningHub result exceeds 50 MB")
                output.write(chunk)
    if total == 0:
        raise ValueError("RunningHub returned an empty image")
    return destination


def main(task: dict) -> dict:
    """Run the AI app and return an image artifact in Glance's Worker format."""
    key = api_key()
    input_path = Path((task.get("input") or {}).get("path", ""))
    if not input_path.is_file():
        raise ValueError("task.input.path must point to a downloaded image")
    width, height = image_dimensions(input_path)
    print(f"Input image dimensions: {width}x{height}")
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    task_id = submit(key, width, height)
    result_url = poll_result_url(key, task_id)
    image_path = download_image(result_url, output_dir)
    print(f"RunningHub image downloaded: {image_path.name} ({image_path.stat().st_size} bytes)")
    return {"outputs": [{"type": "image", "path": str(image_path)}]}
