"""Turn the selected image into text with a RunningHub AI app."""

import os
import json
import time
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from uuid import uuid4


APP_ID = "2084152800765890561"
BASE_URL = "https://www.runninghub.cn"
UPLOAD_URL = f"{BASE_URL}/openapi/v2/media/upload/binary"
RUN_URL = f"{BASE_URL}/openapi/v2/run/ai-app/{APP_ID}"
QUERY_URL = f"{BASE_URL}/openapi/v2/query"
POLL_INTERVAL = 5
POLL_TIMEOUT = 600
MAX_TEXT_BYTES = 1024 * 1024


def post_json(url: str, payload: dict, headers: dict[str, str]) -> dict:
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={**headers, "Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=60) as response:
        data = json.load(response)
    if not isinstance(data, dict):
        raise RuntimeError("RunningHub returned an invalid response")
    return data


def upload_image(image_path: Path, headers: dict[str, str]) -> str:
    boundary = f"glance-{uuid4().hex}"
    suffix = image_path.suffix.lower()
    mime = "image/jpeg" if suffix in (".jpg", ".jpeg") else "image/png"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="input{suffix}"\r\n'
        f"Content-Type: {mime}\r\n\r\n"
    ).encode("utf-8") + image_path.read_bytes() + f"\r\n--{boundary}--\r\n".encode("ascii")
    request = Request(
        UPLOAD_URL,
        data=body,
        headers={**headers, "Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    with urlopen(request, timeout=60) as response:
        data = json.load(response)
    file_name = (data.get("data") or {}).get("fileName") or (data.get("data") or {}).get("filename")
    if data.get("code") not in (0, 200) or not isinstance(file_name, str) or not file_name:
        raise RuntimeError(f"RunningHub upload failed: {data.get('message') or data.get('msg') or 'missing fileName'}")
    return file_name


def submit_task(file_name: str, headers: dict[str, str]) -> str:
    data = post_json(
        RUN_URL,
        {
            "nodeInfoList": [{
                "nodeId": "1",
                "fieldName": "image",
                "fieldValue": file_name,
                "description": "image",
            }],
            "instanceType": "default",
            "usePersonalQueue": "false",
        },
        headers,
    )
    task_id = data.get("taskId")
    if not task_id:
        raise RuntimeError(f"RunningHub did not accept the task: {data.get('errorMessage') or 'missing taskId'}")
    return str(task_id)


def wait_for_results(task_id: str, headers: dict[str, str]) -> list[dict]:
    deadline = time.monotonic() + POLL_TIMEOUT
    while time.monotonic() < deadline:
        data = post_json(QUERY_URL, {"taskId": task_id}, headers)
        status = data.get("status")
        if status == "SUCCESS":
            results = data.get("results")
            if not isinstance(results, list) or not results:
                raise RuntimeError("RunningHub completed the task without a result")
            return results
        if status not in ("RUNNING", "QUEUED"):
            raise RuntimeError(f"RunningHub task failed: {data.get('errorMessage') or status or 'unknown status'}")
        time.sleep(min(POLL_INTERVAL, max(0, deadline - time.monotonic())))
    raise TimeoutError(f"RunningHub task did not finish within {POLL_TIMEOUT} seconds")


def result_text(results: list[dict], headers: dict[str, str]) -> str:
    for result in results:
        if isinstance(result, dict) and isinstance(result.get("text"), str) and result["text"].strip():
            return result["text"].strip()

    for result in results:
        if not isinstance(result, dict):
            continue
        url = result.get("url")
        if not isinstance(url, str) or urlparse(url).scheme != "https":
            continue
        output_type = str(result.get("outputType") or "").lower().lstrip(".")
        suffix = Path(urlparse(url).path).suffix.lower()
        if output_type not in ("txt", "text", "md", "json") and suffix not in (".txt", ".md", ".json"):
            continue
        request = Request(url, headers={"User-Agent": "Glance-Widget/1.0"})
        with urlopen(request, timeout=60) as response:
            content = response.read(MAX_TEXT_BYTES + 1)
        if len(content) > MAX_TEXT_BYTES:
            raise ValueError("RunningHub text result exceeds 1 MB")
        text = content.decode("utf-8-sig").strip()
        if text:
            return text
    raise RuntimeError("RunningHub returned no text result")


def main(task: dict) -> dict:
    image_value = (task.get("input") or {}).get("path")
    image_path = Path(image_value) if image_value else None
    if image_path is None or not image_path.is_file():
        raise ValueError("task.input.path must point to an existing image")
    api_key = os.environ.get("RUNNINGHUB_API_KEY", "").strip()
    if not api_key:
        raise ValueError("RUNNINGHUB_API_KEY is required")

    headers = {"Authorization": f"Bearer {api_key}"}
    file_name = upload_image(image_path, headers)
    task_id = submit_task(file_name, headers)
    text = result_text(wait_for_results(task_id, headers), headers)
    if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
        raise ValueError("RunningHub text result exceeds 1 MB")
    return {"outputs": [{"type": "text", "text": text}]}
