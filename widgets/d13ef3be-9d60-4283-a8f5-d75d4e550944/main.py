"""Expand one image with RunningHub and return the generated image to Glance."""

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

BASE_URL = "https://www.runninghub.ai"
UPLOAD_URL = f"{BASE_URL}/task/openapi/upload"
RUN_URL = f"{BASE_URL}/openapi/v2/run/ai-app/2108809728910839809"
QUERY_URL = f"{BASE_URL}/openapi/v2/query"
POLL_INTERVAL = 5
POLL_TIMEOUT = 600
REQUEST_RETRIES = 3
GENERATION_ATTEMPTS = 3
TOTAL_TIMEOUT = 1200
MAX_IMAGE_BYTES = 50 * 1024 * 1024
MAX_INPUT_BYTES = 30 * 1024 * 1024
IMAGE_MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
              ".webp": "image/webp"}


class AuditRejectedError(RuntimeError):
    """The provider explicitly rejected the content; do not retry."""


class GenerationFailedError(RuntimeError):
    """The provider explicitly failed a generation; a new task may be submitted."""


class SubmissionStateUnknownError(RuntimeError):
    """The submit request may have created a paid task; do not duplicate it."""


def safe_error(value: object, api_key: str) -> str:
    """Avoid exposing the credential in provider error messages."""
    return str(value).replace(api_key, "[REDACTED]")[:500]


def failed_reason(result: dict) -> dict:
    reason = result.get("failedReason") or {}
    if isinstance(reason, str):
        try:
            reason = json.loads(reason)
        except (ValueError, TypeError):
            reason = {"message": reason}
    return reason if isinstance(reason, dict) else {}


def is_audit_rejection(result: dict) -> bool:
    if not isinstance(result, dict):
        return False
    reason = failed_reason(result)
    if "audit" in str(reason.get("exception_type", "")).lower():
        return True
    detail = " ".join(str(value) for value in (
        reason.get("exception_message", ""), reason.get("message", ""),
        result.get("errorMessage", ""), result.get("message", ""),
        result.get("msg", ""),
    )).lower()
    return any(term in detail for term in (
        "porn", "色情", "涉黄", "political", "politics", "涉政", "政治",
    ))


def provider_message(result: dict, api_key: str) -> str:
    reason = failed_reason(result)
    detail = (result.get("errorMessage") or reason.get("exception_message")
              or reason.get("message") or result.get("message") or result.get("msg")
              or result.get("status") or "Unknown provider error")
    return safe_error(detail, api_key)


def request_json(request: Request, operation: str, api_key: str,
                 *, retry_transient: bool = True, deadline: float | None = None) -> dict:
    """Retry safe requests; never blindly repeat an uncertain task submission."""
    attempts = REQUEST_RETRIES if retry_transient else 1
    for attempt in range(1, attempts + 1):
        remaining = deadline - time.monotonic() if deadline is not None else 60
        if remaining <= 0:
            raise TimeoutError(f"RunningHub {operation} exceeded the Widget deadline")
        try:
            with urlopen(request, timeout=min(60, remaining)) as response:
                try:
                    result = json.load(response)
                except ValueError as error:
                    if not retry_transient:
                        raise SubmissionStateUnknownError(
                            "RunningHub submit returned invalid JSON; task status is unknown"
                        ) from error
                    raise RuntimeError(
                        f"RunningHub {operation} returned invalid JSON"
                    ) from error
            if not isinstance(result, dict):
                if not retry_transient:
                    raise SubmissionStateUnknownError(
                        "RunningHub submit returned an invalid response; task status is unknown"
                    )
                raise RuntimeError(f"RunningHub {operation} returned an invalid response")
            return result
        except HTTPError as error:
            detail = error.read(4096).decode("utf-8", errors="replace")
            try:
                detail_json = json.loads(detail)
            except ValueError:
                detail_json = {"errorMessage": detail}
            if isinstance(detail_json, dict) and is_audit_rejection(detail_json):
                raise AuditRejectedError(
                    f"RunningHub content rejected: {provider_message(detail_json, api_key)}"
                ) from None
            if error.code in (401, 403):
                raise RuntimeError(
                    f"RunningHub {operation} authentication failed: HTTP {error.code}"
                ) from None
            if error.code not in (408, 429) and error.code < 500:
                raise RuntimeError(
                    f"RunningHub {operation} failed: HTTP {error.code}, {safe_error(detail, api_key)}"
                ) from error
            failure = f"HTTP {error.code}"
        except (URLError, TimeoutError) as error:
            failure = type(error).__name__
        if not retry_transient:
            raise SubmissionStateUnknownError(
                f"RunningHub submit status is unknown ({failure}); refusing duplicate submission"
            )
        if attempt == attempts:
            raise RuntimeError(f"RunningHub {operation} failed after {attempt} attempts: {failure}")
        logger.warning("RunningHub %s request %d/%d failed (%s); retrying",
                       operation, attempt, attempts, failure)
        time.sleep(min(2 ** attempt, max(0, deadline - time.monotonic()))
                   if deadline is not None else 2 ** attempt)
    raise AssertionError("unreachable")


def post_json(url: str, payload: dict, api_key: str, operation: str,
              *, retry_transient: bool = True, deadline: float | None = None) -> dict:
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        method="POST",
    )
    return request_json(request, operation, api_key, retry_transient=retry_transient,
                        deadline=deadline)


def upload_image(image_path: Path, api_key: str, deadline: float) -> str:
    if not 0 < image_path.stat().st_size <= MAX_INPUT_BYTES:
        raise ValueError("RunningHub input image is empty or exceeds 30 MB")
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
        'Content-Disposition: form-data; name="apiKey"\r\n\r\n'
        f"{api_key}\r\n"
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="fileType"\r\n\r\n'
        "input\r\n"
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
    result = request_json(request, "upload", api_key, deadline=deadline)
    data = result.get("data") or {}
    file_name = (data.get("fileName") or data.get("filename")) if isinstance(data, dict) else None
    if result.get("code") not in (0, 200) or not isinstance(file_name, str) or not file_name:
        if is_audit_rejection(result):
            raise AuditRejectedError(
                f"RunningHub content rejected: {provider_message(result, api_key)}"
            )
        raise RuntimeError(f"RunningHub upload failed: {provider_message(result, api_key)}")
    return file_name


def submit_task(api_key: str, image_name: str, deadline: float) -> str:
    nodes = [
        {"nodeId": "286", "fieldName": "image", "fieldValue": image_name,
         "description": None},
    ]
    result = post_json(RUN_URL, {
        "nodeInfoList": nodes,
        "instanceType": "default",
        "usePersonalQueue": "false",
    }, api_key, "submit", retry_transient=False, deadline=deadline)
    task_id = result.get("taskId")
    if task_id:
        return str(task_id)
    if is_audit_rejection(result):
        raise AuditRejectedError(
            f"RunningHub content rejected: {provider_message(result, api_key)}"
        )
    if str(result.get("errorCode")) in ("400", "401", "403", "422"):
        raise RuntimeError(
            f"RunningHub submit rejected the request: {provider_message(result, api_key)}"
        )
    if result.get("errorCode") or result.get("errorMessage") or result.get("message"):
        raise GenerationFailedError(
            f"RunningHub did not accept the task: {provider_message(result, api_key)}"
        )
    raise SubmissionStateUnknownError("RunningHub submit returned no task ID or failure reason")


def wait_for_result(api_key: str, task_id: str, overall_deadline: float) -> str:
    deadline = min(overall_deadline, time.monotonic() + POLL_TIMEOUT)
    while time.monotonic() < deadline:
        result = post_json(QUERY_URL, {"taskId": task_id}, api_key, "query",
                           deadline=deadline)
        status = result.get("status")
        logger.info("RunningHub task %s: %s", task_id, status)
        if status == "SUCCESS":
            results = result.get("results")
            if not isinstance(results, list) or not results or not isinstance(results[0], dict):
                raise GenerationFailedError("RunningHub completed the task without an image result")
            url = results[0].get("url")
            if not isinstance(url, str) or urlparse(url).scheme != "https":
                raise GenerationFailedError("RunningHub returned an invalid image URL")
            return url
        if status in ("FAILED", "FAILURE", "ERROR"):
            if is_audit_rejection(result):
                raise AuditRejectedError(
                    f"RunningHub content rejected: {provider_message(result, api_key)}"
                )
            raise GenerationFailedError(
                f"RunningHub task failed: {provider_message(result, api_key)}"
            )
        if status not in ("RUNNING", "QUEUED"):
            raise RuntimeError(f"RunningHub returned unknown task status: {safe_error(status, api_key)}")
        time.sleep(min(POLL_INTERVAL, max(0, deadline - time.monotonic())))
    raise TimeoutError(
        f"RunningHub task {task_id} did not finish within the polling deadline; "
        "refusing to submit a duplicate"
    )


def download_image(url: str, output_dir: Path, deadline: float) -> Path:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("RunningHub returned an invalid image URL")
    suffix = Path(parsed.path).suffix.lower()
    if suffix not in IMAGE_MIME:
        suffix = ".png"
    destination = output_dir / f"result-{uuid4().hex}{suffix}"
    for attempt in range(1, REQUEST_RETRIES + 1):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("RunningHub result download exceeded the Widget deadline")
        size = 0
        complete = False
        try:
            with urlopen(Request(url, headers={"User-Agent": "Glance-Widget/1.0"}),
                         timeout=min(60, remaining)) as response:
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
            time.sleep(min(2 ** attempt, max(0, deadline - time.monotonic())))
        finally:
            if not complete and destination.exists():
                destination.unlink()
    raise AssertionError("unreachable")


def main(task: dict) -> dict:
    """Use the selected Glance image for RunningHub node 286."""
    input_path = (task.get("input") or {}).get("path")
    if not isinstance(input_path, str) or not input_path or not Path(input_path).is_file():
        raise ValueError("task.input.path must point to one existing image")
    api_key = os.environ.get("RUNNINGHUB_API_KEY_AI", "").strip()
    if not api_key:
        raise ValueError("RUNNINGHUB_API_KEY_AI is required")
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + TOTAL_TIMEOUT
    uploaded = upload_image(Path(input_path), api_key, deadline)
    for attempt in range(1, GENERATION_ATTEMPTS + 1):
        if time.monotonic() >= deadline:
            raise TimeoutError("RunningHub generation exceeded the Widget deadline")
        try:
            logger.info("RunningHub generation attempt %d/%d", attempt, GENERATION_ATTEMPTS)
            task_id = submit_task(api_key, uploaded, deadline)
            logger.info("RunningHub task submitted: %s", task_id)
            result_url = wait_for_result(api_key, task_id, deadline)
            break
        except GenerationFailedError:
            if attempt == GENERATION_ATTEMPTS or deadline - time.monotonic() < 10:
                raise
            logger.warning("RunningHub generation attempt %d/%d failed; retrying",
                           attempt, GENERATION_ATTEMPTS, exc_info=True)
            time.sleep(min(5 * attempt, max(0, deadline - time.monotonic())))
    output_path = download_image(result_url, output_dir, deadline)
    return {"outputs": [{"type": "image", "path": str(output_path)}]}
