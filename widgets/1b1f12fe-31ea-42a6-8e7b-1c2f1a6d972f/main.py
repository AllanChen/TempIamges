"""Run a RunningHub AI app and return its image result to Glance."""

import argparse
import json
import os
import time
import tempfile
import logging
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import uuid

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

RUNNINGHUB_APP_ID = "1939683977558925314"
RUN_URL = f"https://www.runninghub.cn/openapi/v2/run/ai-app/{RUNNINGHUB_APP_ID}"
QUERY_URL = "https://www.runninghub.cn/openapi/v2/query"
UPLOAD_URL = "https://www.runninghub.cn/task/openapi/upload"

POLL_INTERVAL = 5
POLL_TIMEOUT = 600

MAX_RETRIES = 3
RETRY_BACKOFF = 5


class AuditRejectedError(Exception):
    """RunningHub rejected the task for content moderation."""


def is_audit_rejection(result: dict) -> bool:
    """Detect a RunningHub content-moderation rejection."""
    if not isinstance(result, dict):
        return False

    failed_reason = result.get("failedReason") or {}
    if isinstance(failed_reason, str):
        try:
            failed_reason = json.loads(failed_reason)
        except (ValueError, TypeError):
            failed_reason = {}
    if not isinstance(failed_reason, dict):
        failed_reason = {}

    exception_type = str(failed_reason.get("exception_type", "")).lower()
    exception_message = str(failed_reason.get("exception_message", "")).lower()

    if "rhauditexception" in exception_type or "audit" in exception_type:
        return True
    if exception_message == "porn":
        return True
    return False


def get_api_key() -> str:
    """Read the RunningHub key from the Widget process environment."""
    return os.environ.get("RUNNINGHUB_API_KEY", "")


def safe_error(value: object, api_key: str) -> str:
    """Keep provider errors useful without writing the credential to logs."""
    return str(value).replace(api_key, "[REDACTED]")[:500]


def post_json(url: str, payload: dict, api_key: str, operation: str) -> dict:
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    return send_json(request, api_key, operation)


def send_json(request: Request, api_key: str, operation: str) -> dict:
    try:
        with urlopen(request, timeout=60) as response:
            result = json.load(response)
    except HTTPError as error:
        detail = error.read(4096).decode("utf-8", errors="replace")
        raise RuntimeError(
            f"RunningHub {operation} error: HTTP {error.code}, {safe_error(detail, api_key)}"
        ) from error
    if not isinstance(result, dict):
        raise RuntimeError(f"RunningHub {operation} returned an invalid response")
    return result


def upload_input(api_key: str, input_path: Path) -> str:
    """Upload the local input to RunningHub and return its hosted file name."""
    logger.info("Uploading input to RunningHub: %s (%d bytes)", input_path.name, input_path.stat().st_size)
    boundary = f"glance-{uuid.uuid4().hex}"
    suffix = input_path.suffix.lower()
    if suffix not in (".png", ".jpg", ".jpeg", ".webp"):
        suffix = ".bin"
    content_type = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
    }.get(suffix, "application/octet-stream")
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="apiKey"\r\n\r\n{api_key}\r\n',
        f'--{boundary}\r\nContent-Disposition: form-data; name="fileType"\r\n\r\nimage\r\n',
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="input{suffix}"\r\n'
        f'Content-Type: {content_type}\r\n\r\n',
    ]
    body = b"".join(part.encode("utf-8") for part in parts)
    body += input_path.read_bytes() + f"\r\n--{boundary}--\r\n".encode("ascii")
    request = Request(
        UPLOAD_URL,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    result = send_json(request, api_key, "upload")
    if result.get("code") != 0 or not (result.get("data") or {}).get("fileName"):
        raise RuntimeError(f"RunningHub upload failed: {safe_error(result.get('msg', result), api_key)}")
    file_name = result["data"]["fileName"]
    logger.info("RunningHub upload complete: fileName=%s", Path(urlparse(file_name).path).name)
    return file_name


def submit_task(api_key: str, rh_filename: str) -> str:
    """Submit the task to RunningHub and return the taskId."""
    payload = {
        "nodeInfoList": [
            {
                "nodeId": "191",
                "fieldName": "image",
                "fieldValue": rh_filename,
                "description": "上传水印图",
            }
        ],
        "instanceType": "default",
        "usePersonalQueue": "false",
    }

    logger.info("Submitting RunningHub task for app %s ...", RUNNINGHUB_APP_ID)
    result = post_json(RUN_URL, payload, api_key, "submit")
    task_id = result.get("taskId")
    if not task_id:
        raise RuntimeError(f"RunningHub submit returned no taskId: {safe_error(result, api_key)}")
    logger.info("Task submitted. Task ID: %s", task_id)
    return task_id


def poll_task(api_key: str, task_id: str) -> str:
    """Poll RunningHub task until SUCCESS, return the first result URL."""
    begin = time.monotonic()
    query_count = 0

    while True:
        if time.monotonic() - begin > POLL_TIMEOUT:
            raise TimeoutError(f"RunningHub task {task_id} timed out after {POLL_TIMEOUT}s")

        result = post_json(QUERY_URL, {"taskId": task_id}, api_key, "query")
        query_count += 1
        status = result.get("status")
        logger.info("Task status: taskID=%s, query=%d, status=%s", task_id, query_count, status)

        if status == "SUCCESS":
            results = result.get("results") or []
            if not results:
                raise RuntimeError("Task completed but no results found.")
            output_url = results[0].get("url")
            if not output_url:
                raise RuntimeError(f"Task completed but result has no url: {safe_error(results[0], api_key)}")
            logger.info("Task completed. URL: %s", output_url)
            return output_url
        elif status in ("RUNNING", "QUEUED"):
            time.sleep(POLL_INTERVAL)
        else:
            error_message = safe_error(result.get("errorMessage", "Unknown error"), api_key)
            if is_audit_rejection(result):
                raise AuditRejectedError(
                    f"RunningHub content rejected (audit): {error_message} "
                    f"errorCode={result.get('errorCode')}"
                )
            raise RuntimeError(f"RunningHub task failed: {error_message} (status={status})")


def download_image(url: str, directory: Path) -> Path:
    """Save the provider image so the Worker can upload it as an image artifact."""
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("RunningHub returned an invalid image URL")
    suffix = Path(parsed.path).suffix.lower()
    if suffix not in (".png", ".jpg", ".jpeg", ".webp"):
        suffix = ".png"
    size = 0
    request = Request(url, headers={"User-Agent": "Glance-Widget/1.0"})
    with urlopen(request, timeout=60) as response:
        headers = getattr(response, "headers", None)
        mime = headers.get_content_type() if headers is not None else None
        suffix = {"image/png": ".png", "image/jpeg": ".jpg",
                  "image/webp": ".webp"}.get(mime, suffix)
        destination = directory / f"result-{uuid.uuid4().hex}{suffix}"
        with destination.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > 50 * 1024 * 1024:
                    raise ValueError("RunningHub result exceeds 50 MB")
                output.write(chunk)
    if size == 0:
        raise ValueError("RunningHub returned an empty image")
    return destination


def main(task: dict) -> dict:
    """Process the image uploaded by Glance and return a local image artifact."""
    input_path = Path((task.get("input") or {}).get("path", ""))
    if not input_path.is_file():
        raise ValueError("task.input.path must point to an existing image")
    api_key = get_api_key()
    if not api_key:
        raise ValueError("RUNNINGHUB_API_KEY is required")

    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)

    rh_filename = upload_input(api_key, input_path)

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            logger.info("RunningHub attempt %d/%d", attempt, MAX_RETRIES)
            task_id = submit_task(api_key, rh_filename)
            result_url = poll_task(api_key, task_id)
            break
        except AuditRejectedError:
            raise
        except Exception:
            if attempt == MAX_RETRIES:
                raise
            logger.warning("RunningHub attempt %d/%d failed; retrying", attempt, MAX_RETRIES, exc_info=True)
            time.sleep(RETRY_BACKOFF)

    output_path = download_image(result_url, output_dir)
    return {"outputs": [{"type": "image", "path": str(output_path)}]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run this Widget on a local image")
    parser.add_argument("image", type=Path)
    arguments = parser.parse_args()
    print(json.dumps(main({"input": {"path": str(arguments.image)}}), ensure_ascii=False))
