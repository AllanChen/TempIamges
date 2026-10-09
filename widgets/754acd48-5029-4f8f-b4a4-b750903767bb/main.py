"""Run the two-image RunningHub outfit workflow and return its image to Glance."""

import json
import logging
import os
import tempfile
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from uuid import uuid4


logger = logging.getLogger(__name__)

BASE_URL = "https://www.runninghub.cn"
UPLOAD_URL = f"{BASE_URL}/openapi/v2/media/upload/binary"
RUN_URL = f"{BASE_URL}/openapi/v2/run/ai-app/2108493566690545665"
QUERY_URL = f"{BASE_URL}/openapi/v2/query"
POLL_INTERVAL = 5
POLL_TIMEOUT = 600
REQUEST_RETRIES = 3
MAX_IMAGE_BYTES = 50 * 1024 * 1024
IMAGE_MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
              ".webp": "image/webp"}


def safe_error(value: object, api_key: str) -> str:
    """Avoid exposing the credential in provider error messages."""
    return str(value).replace(api_key, "[REDACTED]")[:500]


def request_json(request: Request, operation: str, api_key: str) -> dict:
    """Retry transient transport, rate-limit and server errors only."""
    for attempt in range(1, REQUEST_RETRIES + 1):
        try:
            with urlopen(request, timeout=60) as response:
                result = json.load(response)
            if not isinstance(result, dict):
                raise RuntimeError(f"RunningHub {operation} returned an invalid response")
            return result
        except HTTPError as error:
            detail = error.read(4096).decode("utf-8", errors="replace")
            if error.code not in (408, 429) and error.code < 500:
                raise RuntimeError(
                    f"RunningHub {operation} failed: HTTP {error.code}, {safe_error(detail, api_key)}"
                ) from error
            failure = f"HTTP {error.code}, {safe_error(detail, api_key)}"
        except (URLError, TimeoutError) as error:
            failure = type(error).__name__
        if attempt == REQUEST_RETRIES:
            raise RuntimeError(f"RunningHub {operation} failed after {attempt} attempts: {failure}")
        logger.warning("RunningHub %s attempt %d/%d failed (%s); retrying",
                       operation, attempt, REQUEST_RETRIES, failure)
        time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def post_json(url: str, payload: dict, api_key: str, operation: str) -> dict:
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        method="POST",
    )
    return request_json(request, operation, api_key)


def upload_image(image_path: Path, api_key: str) -> str:
    if image_path.stat().st_size > MAX_IMAGE_BYTES:
        raise ValueError("RunningHub input image exceeds 50 MB")
    content = image_path.read_bytes()
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        suffix = ".png"
    elif content.startswith(b"\xff\xd8\xff"):
        suffix = ".jpg"
    elif content.startswith(b"RIFF") and content[8:12] == b"WEBP":
        suffix = ".webp"
    else:
        raise ValueError("This Widget requires PNG, JPEG or WebP input images")
    boundary = f"glance-{uuid4().hex}"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="input{suffix}"\r\n'
        f"Content-Type: {IMAGE_MIME[suffix]}\r\n\r\n"
    ).encode("utf-8") + content + f"\r\n--{boundary}--\r\n".encode("ascii")
    request = Request(
        UPLOAD_URL,
        data=body,
        headers={"Authorization": f"Bearer {api_key}",
                 "Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    result = request_json(request, "upload", api_key)
    data = result.get("data") or {}
    file_name = (data.get("fileName") or data.get("filename")) if isinstance(data, dict) else None
    if result.get("code") not in (0, 200) or not isinstance(file_name, str) or not file_name:
        raise RuntimeError(f"RunningHub upload failed: {safe_error(result.get('message') or result.get('msg') or result, api_key)}")
    return file_name


def submit_task(api_key: str, first_image: str, second_image: str) -> str:
    nodes = [
        {"nodeId": node_id, "fieldName": "image", "fieldValue": file_name, "description": "image"}
        for node_id, file_name in (("207", first_image), ("208", second_image))
    ]
    result = post_json(RUN_URL, {
        "nodeInfoList": nodes,
        "instanceType": "default",
        "usePersonalQueue": "false",
    }, api_key, "submit")
    task_id = result.get("taskId")
    if not task_id:
        raise RuntimeError(f"RunningHub did not accept the task: {safe_error(result.get('errorMessage') or result, api_key)}")
    return str(task_id)


def wait_for_result(api_key: str, task_id: str) -> str:
    deadline = time.monotonic() + POLL_TIMEOUT
    while time.monotonic() < deadline:
        result = post_json(QUERY_URL, {"taskId": task_id}, api_key, "query")
        status = result.get("status")
        logger.info("RunningHub task %s: %s", task_id, status)
        if status == "SUCCESS":
            results = result.get("results")
            if not isinstance(results, list) or not results or not isinstance(results[0], dict):
                raise RuntimeError("RunningHub completed the task without an image result")
            url = results[0].get("url")
            if not isinstance(url, str) or urlparse(url).scheme != "https":
                raise RuntimeError("RunningHub returned an invalid image URL")
            return url
        if status not in ("RUNNING", "QUEUED"):
            raise RuntimeError(f"RunningHub task failed: {safe_error(result.get('errorMessage') or status or 'unknown status', api_key)}")
        time.sleep(min(POLL_INTERVAL, max(0, deadline - time.monotonic())))
    raise TimeoutError(f"RunningHub task {task_id} did not finish within {POLL_TIMEOUT} seconds")


def download_image(url: str, output_dir: Path) -> Path:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("RunningHub returned an invalid image URL")
    suffix = Path(parsed.path).suffix.lower()
    if suffix not in IMAGE_MIME:
        suffix = ".png"
    destination = output_dir / f"result-{uuid4().hex}{suffix}"
    for attempt in range(1, REQUEST_RETRIES + 1):
        size = 0
        complete = False
        try:
            with urlopen(Request(url, headers={"User-Agent": "Glance-Widget/1.0"}), timeout=60) as response:
                mime = response.headers.get_content_type()
                if mime not in (*IMAGE_MIME.values(), "image/webp"):
                    raise ValueError(f"RunningHub returned non-image content: {mime}")
                suffix = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}[mime]
                destination = destination.with_suffix(suffix)
                with destination.open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        size += len(chunk)
                        if size > MAX_IMAGE_BYTES:
                            raise ValueError("RunningHub result exceeds 50 MB")
                        output.write(chunk)
            if size == 0:
                raise ValueError("RunningHub returned an empty image")
            complete = True
            return destination
        except (HTTPError, URLError, TimeoutError) as error:
            retryable = not isinstance(error, HTTPError) or error.code in (408, 429) or error.code >= 500
            if not retryable or attempt == REQUEST_RETRIES:
                raise RuntimeError(f"RunningHub result download failed: {type(error).__name__}") from error
            logger.warning("RunningHub download attempt %d/%d failed; retrying", attempt, REQUEST_RETRIES)
            time.sleep(2 ** attempt)
        finally:
            if not complete and destination.exists():
                destination.unlink()
    raise AssertionError("unreachable")


def main(task: dict) -> dict:
    """Use the first image for node 207 and the second for node 208."""
    paths = (task.get("input") or {}).get("imagePaths")
    if not isinstance(paths, list) or len(paths) != 2:
        raise ValueError("This Widget requires exactly two input images")
    images = [Path(value) for value in paths if isinstance(value, str) and value]
    if len(images) != 2 or any(not path.is_file() for path in images):
        raise ValueError("task.input.imagePaths must contain two existing images")
    api_key = os.environ.get("RUNNINGHUB_API_KEY", "").strip()
    if not api_key:
        raise ValueError("RUNNINGHUB_API_KEY is required")

    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    uploaded = [upload_image(image, api_key) for image in images]
    task_id = submit_task(api_key, uploaded[0], uploaded[1])
    logger.info("RunningHub task submitted: %s", task_id)
    result_url = wait_for_result(api_key, task_id)
    output_path = download_image(result_url, output_dir)
    return {"outputs": [{"type": "image", "path": str(output_path)}]}
