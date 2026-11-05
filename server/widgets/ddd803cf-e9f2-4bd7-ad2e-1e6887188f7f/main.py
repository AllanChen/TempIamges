"""Upscale an image with RunningHub and return a local image to Glance."""

import argparse
import os
import json
import time
import tempfile
import logging
from pathlib import Path
from urllib.parse import urlparse
import uuid
import requests

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

RUNNINGHUB_APP_ID = "2097856100338065410"
RUN_URL = f"https://www.runninghub.cn/openapi/v2/run/ai-app/{RUNNINGHUB_APP_ID}"
QUERY_URL = "https://www.runninghub.cn/openapi/v2/query"

POLL_INTERVAL = 5
POLL_TIMEOUT = 1200

ALLOWED_RESOLUTIONS = ("1k", "2k", "4k")
DEFAULT_RESOLUTION = "4k"

MAX_RETRIES = 3
RETRY_BACKOFF = 5  # seconds between retries


class AuditRejectedError(Exception):
    """RunningHub rejected the task for content moderation (Porn / audit).

    This is a terminal, non-retryable failure: retrying the exact same input
    will always be rejected, so we surface the error immediately.
    """


def is_audit_rejection(result: dict) -> bool:
    """Detect a RunningHub content-moderation (audit) rejection.

    Matches responses like errorCode 805 with a RHAuditException, e.g.
    failedReason.exception_type == "audit.RHAuditException" or
    failedReason.exception_message == "Porn".
    """
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


def upload_input(api_key: str, input_path: Path) -> str:
    """Upload the local input to RunningHub and return its hosted file name."""
    started = time.monotonic()
    logger.info("RunningHub 上传输入图片：文件=%s，大小=%d 字节", input_path.name, input_path.stat().st_size)
    with input_path.open("rb") as stream:
        response = requests.post(
            "https://www.runninghub.cn/task/openapi/upload",
            data={"apiKey": api_key, "fileType": "image"},
            files={"file": (input_path.name, stream)}, timeout=60,
        )
    logger.info("RunningHub 输入上传响应：HTTP %d，耗时=%.1f 秒", response.status_code, time.monotonic() - started)
    response.raise_for_status()
    result = response.json()
    if result.get("code") != 0 or not (result.get("data") or {}).get("fileName"):
        raise RuntimeError(f"RunningHub upload failed: {safe_error(result.get('msg', result), api_key)}")
    filename = result["data"]["fileName"]
    logger.info("RunningHub 输入上传完成：fileName=%s", Path(urlparse(filename).path).name)
    return filename


def download_image(url: str, directory: Path) -> Path:
    """Download a result into the current task's temporary output directory."""
    parsed = urlparse(url)
    suffix = Path(parsed.path).suffix.lower()
    if suffix not in {".png", ".jpg", ".jpeg", ".webp"}:
        suffix = ".png"
    destination = directory / f"result-{uuid.uuid4().hex}{suffix}"
    started = time.monotonic()
    logger.info("下载 RunningHub 结果图片：来源=%s，文件=%s", parsed.hostname, Path(parsed.path).name)
    try:
        with requests.get(url, stream=True, timeout=60) as response:
            logger.info("RunningHub 结果下载响应：HTTP %d", response.status_code)
            if not 200 <= response.status_code < 300:
                raise RuntimeError(f"RunningHub result download HTTP {response.status_code}")
            size = 0
            next_report = 5 * 1024 * 1024
            with destination.open("wb") as output:
                for chunk in response.iter_content(chunk_size=1024 * 1024):
                    size += len(chunk)
                    if size > 50 * 1024 * 1024:
                        raise ValueError("RunningHub result exceeds 50 MB")
                    output.write(chunk)
                    if size >= next_report:
                        logger.info("RunningHub 结果下载进度：%.1f MB", size / (1024 * 1024))
                        next_report += 5 * 1024 * 1024
    except requests.RequestException as error:
        raise RuntimeError(f"RunningHub result download failed: {type(error).__name__}") from None
    if size == 0:
        raise ValueError("RunningHub returned an empty image")
    logger.info("RunningHub 结果下载完成：文件=%s，大小=%d 字节，耗时=%.1f 秒",
                destination.name, size, time.monotonic() - started)
    return destination


def submit_upscale_task(api_key: str, rh_filename: str, resolution: str) -> str:
    """Submit an upscale task to RunningHub AI app, return taskId."""
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    payload = {
        "nodeInfoList": [
            {
                "nodeId": "11",
                "fieldName": "image",
                "fieldValue": rh_filename,
                "description": "image",
            },
            {
                "nodeId": "14",
                "fieldName": "resolution",
                "fieldData": '[["1k", "2k", "4k"], {"default": "2k"}]',
                "fieldValue": resolution,
                "description": "resolution",
            },
        ],
        "instanceType": "default",
        "usePersonalQueue": "false",
    }

    started = time.monotonic()
    logger.info("提交 RunningHub 超分任务：appID=%s，分辨率=%s", RUNNINGHUB_APP_ID, resolution)
    response = requests.post(RUN_URL, headers=headers, data=json.dumps(payload), timeout=60)
    logger.info("RunningHub 提交响应：HTTP %d，耗时=%.1f 秒", response.status_code, time.monotonic() - started)
    if response.status_code != 200:
        raise RuntimeError(f"RunningHub submit error: {response.status_code}, {safe_error(response.text, api_key)}")

    result = response.json()
    task_id = result.get("taskId")
    if not task_id:
        raise RuntimeError(f"RunningHub submit returned no taskId: {safe_error(result, api_key)}")
    logger.info("RunningHub 任务已提交：taskID=%s", task_id)
    return task_id


def poll_task(api_key: str, task_id: str) -> str:
    """Poll RunningHub task until SUCCESS, return the first result URL."""
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    begin = time.time()
    query_count = 0
    logger.info("开始查询 RunningHub 任务：taskID=%s，最长等待=%d 秒", task_id, POLL_TIMEOUT)

    while True:
        if time.time() - begin > POLL_TIMEOUT:
            raise Exception(f"RunningHub task {task_id} timed out after {POLL_TIMEOUT}s")

        response = requests.post(
            QUERY_URL, headers=headers, data=json.dumps({"taskId": task_id}), timeout=60
        )
        query_count += 1
        if response.status_code != 200:
            raise RuntimeError(f"RunningHub query error: {response.status_code}, {safe_error(response.text, api_key)}")

        result = response.json()
        status = result.get("status")
        logger.info("RunningHub 任务状态：taskID=%s，查询=%d，状态=%s，已等待=%.1f 秒",
                    task_id, query_count, status, time.time() - begin)

        if status == "SUCCESS":
            results = result.get("results") or []
            if not results:
                raise Exception("Task completed but no results found.")
            output_url = results[0].get("url")
            if not output_url:
                raise RuntimeError(f"Task completed but result has no url: {safe_error(results[0], api_key)}")
            parsed = urlparse(output_url)
            logger.info("RunningHub 任务成功：taskID=%s，结果数=%d，结果来源=%s，文件=%s",
                        task_id, len(results), parsed.hostname, Path(parsed.path).name)
            logger.info("RunningHub 返回结果 URL（省略查询参数）：%s://%s%s",
                        parsed.scheme, parsed.netloc, parsed.path)
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
            raise Exception(f"RunningHub task failed: {error_message} (status={status})")


def main(task: dict) -> dict:
    """Process the image already downloaded by glance worker."""
    input_path = Path((task.get("input") or {}).get("path", ""))
    if not input_path.is_file():
        raise ValueError("task.input.path must point to an existing image")
    api_key = get_api_key()
    if not api_key:
        raise ValueError("RUNNINGHUB_API_KEY is required")
    resolution = str((task.get("parameters") or {}).get("resolution", DEFAULT_RESOLUTION)).lower().strip()
    if resolution not in ALLOWED_RESOLUTIONS:
        raise ValueError(f"resolution must be one of {', '.join(ALLOWED_RESOLUTIONS)}")
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    logger.info("开始超分：Glance任务=%s，输入=%s，大小=%d 字节，分辨率=%s",
                task.get("taskId", "local"), input_path.name, input_path.stat().st_size, resolution)
    rh_filename = upload_input(api_key, input_path)
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            logger.info("RunningHub 执行尝试：%d/%d", attempt, MAX_RETRIES)
            task_id = submit_upscale_task(api_key, rh_filename, resolution)
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
    logger.info("超分结果准备完成：文件=%s，大小=%d 字节", output_path.name, output_path.stat().st_size)
    return {"outputs": [{"type": "image", "path": str(output_path)}]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run this Widget on a local image")
    parser.add_argument("image", type=Path)
    parser.add_argument("--resolution", choices=ALLOWED_RESOLUTIONS, default=DEFAULT_RESOLUTION)
    arguments = parser.parse_args()
    print(json.dumps(main({"input": {"path": str(arguments.image)},
                           "parameters": {"resolution": arguments.resolution}}), ensure_ascii=False))
