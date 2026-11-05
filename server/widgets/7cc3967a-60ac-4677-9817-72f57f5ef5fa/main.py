"""Remove an image background with RunningHub and return a local image to Glance."""

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

RUNNINGHUB_APP_ID = "2071773965567217666"
RUN_URL = f"https://www.runninghub.cn/openapi/v2/run/ai-app/{RUNNINGHUB_APP_ID}"
QUERY_URL = "https://www.runninghub.cn/openapi/v2/query"

POLL_INTERVAL = 5
POLL_TIMEOUT = 600  # 10 minutes max

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


def upload_input(api_key: str, input_path: Path) -> str:
    """Upload the local input to RunningHub and return its hosted file name."""
    with input_path.open("rb") as stream:
        response = requests.post(
            "https://www.runninghub.cn/task/openapi/upload",
            data={"apiKey": api_key, "fileType": "image"},
            files={"file": (input_path.name, stream)}, timeout=60,
        )
    response.raise_for_status()
    result = response.json()
    if result.get("code") != 0 or not (result.get("data") or {}).get("fileName"):
        raise RuntimeError(f"RunningHub upload failed: {result.get('msg', result)}")
    return result["data"]["fileName"]


def download_image(url: str, directory: Path) -> Path:
    """Download a result into the current task's temporary output directory."""
    suffix = Path(urlparse(url).path).suffix.lower()
    if suffix not in {".png", ".jpg", ".jpeg", ".webp"}:
        suffix = ".png"
    destination = directory / f"result-{uuid.uuid4().hex}{suffix}"
    with requests.get(url, stream=True, timeout=60) as response:
        response.raise_for_status()
        size = 0
        with destination.open("wb") as output:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                size += len(chunk)
                if size > 50 * 1024 * 1024:
                    raise ValueError("RunningHub result exceeds 50 MB")
                output.write(chunk)
    if size == 0:
        raise ValueError("RunningHub returned an empty image")
    return destination


def submit_removebg_task(api_key: str, rh_filename: str) -> str:
    """Submit removebg task to RunningHub AI app, return taskId."""
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    payload = {
        "nodeInfoList": [
            {
                "nodeId": "3",
                "fieldName": "image",
                "fieldValue": rh_filename,
                "description": "image",
            }
        ],
        "instanceType": "default",
        "usePersonalQueue": "false",
    }

    logger.info("Submitting removebg task to RunningHub app %s ...", RUNNINGHUB_APP_ID)
    response = requests.post(RUN_URL, headers=headers, data=json.dumps(payload), timeout=60)
    if response.status_code != 200:
        raise Exception(f"RunningHub submit error: {response.status_code}, {response.text}")

    result = response.json()
    task_id = result.get("taskId")
    if not task_id:
        raise Exception(f"RunningHub submit returned no taskId: {result}")
    logger.info("Task submitted successfully. Task ID: %s", task_id)
    return task_id


def poll_task(api_key: str, task_id: str) -> str:
    """Poll RunningHub task until SUCCESS, return the first result URL."""
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    begin = time.time()

    while True:
        if time.time() - begin > POLL_TIMEOUT:
            raise Exception(f"RunningHub task {task_id} timed out after {POLL_TIMEOUT}s")

        response = requests.post(
            QUERY_URL, headers=headers, data=json.dumps({"taskId": task_id}), timeout=60
        )
        if response.status_code != 200:
            raise Exception(f"RunningHub query error: {response.status_code}, {response.text}")

        result = response.json()
        status = result.get("status")

        if status == "SUCCESS":
            logger.info("Task completed in %.2f seconds.", time.time() - begin)
            results = result.get("results") or []
            if not results:
                raise Exception("Task completed but no results found.")
            output_url = results[0].get("url")
            if not output_url:
                raise Exception(f"Task completed but result has no url: {results[0]}")
            logger.info("RunningHub result URL: %s", output_url)
            return output_url
        elif status in ("RUNNING", "QUEUED"):
            logger.info("Task still processing. Status: %s", status)
            time.sleep(POLL_INTERVAL)
        else:
            error_message = result.get("errorMessage", "Unknown error")
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
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    rh_filename = upload_input(api_key, input_path)
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            task_id = submit_removebg_task(api_key, rh_filename)
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
