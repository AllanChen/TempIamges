"""Remove described objects with the same RunningHub app as Watermark Remover."""

import argparse
import json
import logging
import os
from pathlib import Path
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import uuid

from PIL import Image

logger = logging.getLogger(__name__)
RUNNINGHUB_APP_ID = "2117102824717897730"
RUN_URL = f"https://www.runninghub.cn/openapi/v2/run/ai-app/{RUNNINGHUB_APP_ID}"
QUERY_URL = "https://www.runninghub.cn/openapi/v2/query"
UPLOAD_URL = "https://www.runninghub.cn/task/openapi/upload"
TOTAL_TIMEOUT = 900  # Includes upload, all attempts, polling and download; runtime allows 1500 s.
MAX_ATTEMPTS = 3
REQUEST_ATTEMPTS = 3
POLL_INTERVAL = 5
MAX_BYTES = 50 * 1024 * 1024
FORMATS = {"PNG": (".png", "image/png"), "JPEG": (".jpg", "image/jpeg"),
           "WEBP": (".webp", "image/webp")}


class PermanentError(RuntimeError):
    """Invalid input, permission error or a provider refusal; never retry."""


class AuditRejectedError(PermanentError):
    pass


class GenerationFailed(RuntimeError):
    """Provider explicitly confirmed generation failed; a new attempt is safe."""


def safe_error(value, key):
    text = str(value)
    return (text.replace(key, "[REDACTED]") if key else text)[:500]


def remaining(deadline):
    seconds = deadline - time.monotonic()
    if seconds <= 0:
        raise TimeoutError("处理超时，请稍后重试 / Processing timed out; please try again later.")
    return min(60, seconds)


def pause(deadline, seconds=POLL_INTERVAL):
    time.sleep(min(seconds, remaining(deadline)))


def retry_step(action, deadline):
    for attempt in range(REQUEST_ATTEMPTS):
        remaining(deadline)
        try:
            return action()
        except (PermanentError, ValueError):
            raise
        except (OSError, URLError, RuntimeError):
            if attempt == REQUEST_ATTEMPTS - 1:
                raise
            pause(deadline)


def is_audit_rejection(result):
    # Inspect provider error fields only, never user input or arbitrary task data.
    reason = result.get("failedReason") or {}
    if isinstance(reason, str):
        try:
            reason = json.loads(reason)
        except ValueError:
            reason = {"exception_message": reason}
    if not isinstance(reason, dict):
        reason = {}
    error = " ".join(str(v) for v in (
        result.get("errorCode", ""), result.get("errorMessage", ""),
        reason.get("exception_type", ""), reason.get("exception_message", ""),
    )).lower()
    return any(term in error for term in (
        "rhauditexception", "porn", "content moderation", "content rejected",
        "political", "色情", "涉政", "政治", "审核拒绝", "内容审核",
    ))


def request_json(request, key, deadline):
    try:
        with urlopen(request, timeout=remaining(deadline)) as response:
            result = json.load(response)
    except HTTPError as error:
        detail = safe_error(error.read(4096).decode("utf-8", errors="replace"), key)
        kind = RuntimeError if error.code in (408, 429) or error.code >= 500 else PermanentError
        raise kind(f"RunningHub HTTP {error.code}: {detail}") from None
    if not isinstance(result, dict):
        raise PermanentError("RunningHub returned an invalid response.")
    return result


def post_json(url, payload, key, deadline):
    request = Request(url, data=json.dumps(payload).encode(), method="POST",
                      headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    return request_json(request, key, deadline)


def image_format(path):
    if not path.is_file() or not 0 < path.stat().st_size <= MAX_BYTES:
        raise ValueError("请选择一张不超过 50 MB 的有效图片 / Select a valid image up to 50 MB.")
    try:
        with Image.open(path) as image:
            fmt = image.format
            if fmt not in FORMATS or getattr(image, "n_frames", 1) != 1:
                raise ValueError("仅支持单帧 PNG、JPEG、WebP / Only still PNG, JPEG and WebP are supported.")
            image.verify()
        with Image.open(path) as image:
            image.load()
    except (OSError, Image.DecompressionBombError) as error:
        raise ValueError("图片无法读取 / The image could not be decoded.") from error
    return fmt


def build_prompt(description):
    if not isinstance(description, str) or not description.strip() or len(description.strip()) > 2000:
        raise ValueError("请描述要移除的物体（1–2000 字）/ Describe the objects to remove (1–2000 characters).")
    # Put the actual edit first; long instructions before the target made the
    # provider ignore the requested object in a real integration test.
    description = description.strip()
    if any('\u3400' <= char <= '\u9fff' for char in description):
        raise ValueError("请使用英文描述要移除的物体，例如 Remove the red ball. / Please describe the objects to remove in English.")
    return description + "\nRemove only the described targets and fill the background naturally. Keep everything else in its original position, size and composition."


def upload_input(path, fmt, key, deadline):
    suffix, mime = FORMATS[fmt]
    boundary = "glance-" + uuid.uuid4().hex
    body = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="apiKey"\r\n\r\n{key}\r\n'
        f'--{boundary}\r\nContent-Disposition: form-data; name="fileType"\r\n\r\nimage\r\n'
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="input{suffix}"\r\n'
        f'Content-Type: {mime}\r\n\r\n'
    ).encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    request = Request(UPLOAD_URL, data=body, method="POST",
                      headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    result = request_json(request, key, deadline)
    filename = (result.get("data") or {}).get("fileName")
    if result.get("code") != 0 or not isinstance(filename, str) or not filename:
        raise PermanentError("RunningHub upload failed: " + safe_error(result.get("msg", result), key))
    return filename


def submit_task(filename, prompt, key, deadline):
    payload = {"nodeInfoList": [
        {"nodeId": "6", "fieldName": "text", "fieldValue": prompt, "description": "text"},
        {"nodeId": "191", "fieldName": "image", "fieldValue": filename, "description": "image"},
    ], "instanceType": "default", "usePersonalQueue": "false"}
    # Submission is deliberately not retried after a timeout: it might already be billable.
    result = post_json(RUN_URL, payload, key, deadline)
    if is_audit_rejection(result):
        raise AuditRejectedError("内容审核未通过，请修改输入 / Content rejected; please revise the input.")
    task_id = result.get("taskId")
    if not task_id:
        raise PermanentError("RunningHub submission was not confirmed: " + safe_error(result, key))
    logger.info("RunningHub task submitted: %s", task_id)
    return task_id


def poll_task(task_id, key, deadline):
    while True:
        result = retry_step(lambda: post_json(QUERY_URL, {"taskId": task_id}, key, deadline), deadline)
        status = result.get("status")
        if status == "SUCCESS":
            results = result.get("results") or []
            if not results or not results[0].get("url"):
                raise PermanentError("RunningHub completed without an image result.")
            return results[0]["url"]
        if is_audit_rejection(result):
            raise AuditRejectedError("内容审核未通过，请修改输入 / Content rejected; please revise the input.")
        if status == "FAILED":
            raise GenerationFailed("RunningHub generation failed: " + safe_error(result.get("errorMessage", "Unknown error"), key))
        if status not in ("QUEUED", "RUNNING"):
            raise PermanentError("Unexpected RunningHub task status: " + safe_error(status, key))
        pause(deadline)


def download_image(url, directory, deadline):
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise PermanentError("RunningHub returned an invalid image URL.")
    destination = directory / ("result-" + uuid.uuid4().hex + ".part")
    try:
        with urlopen(Request(url, headers={"User-Agent": "Glance-Widget/1.0"}),
                     timeout=remaining(deadline)) as response, destination.open("wb") as output:
            size = 0
            while chunk := response.read(1024 * 1024):
                remaining(deadline)
                size += len(chunk)
                if size > MAX_BYTES:
                    raise ValueError("生成图片超过 50 MB / Result exceeds 50 MB.")
                output.write(chunk)
        fmt = image_format(destination)
        return destination.rename(destination.with_suffix(FORMATS[fmt][0]))
    except HTTPError as error:
        if error.code not in (408, 429) and error.code < 500:
            raise PermanentError(f"Result download failed: HTTP {error.code}") from None
        raise
    finally:
        destination.unlink(missing_ok=True)


def main(task):
    deadline = time.monotonic() + TOTAL_TIMEOUT
    prompt = build_prompt((task.get("parameters") or {}).get("prompt"))
    inputs = task.get("input") or {}
    paths = inputs.get("imagePaths")
    if paths is not None and (not isinstance(paths, list) or len(paths) != 1):
        raise ValueError("只能输入一张图片 / Exactly one image is required.")
    path = Path(inputs.get("path") or (paths[0] if paths else "")).resolve()
    fmt = image_format(path)
    key = os.environ.get("RUNNINGHUB_API_KEY", "")
    if not key:
        raise PermanentError("RUNNINGHUB_API_KEY is required.")
    directory = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or tempfile.mkdtemp(prefix="glance-remove-objects-")).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    try:
        filename = retry_step(lambda: upload_input(path, fmt, key, deadline), deadline)
        for attempt in range(MAX_ATTEMPTS):
            task_id = submit_task(filename, prompt, key, deadline)
            try:
                url = poll_task(task_id, key, deadline)
                break
            except GenerationFailed:
                if attempt == MAX_ATTEMPTS - 1:
                    raise
                logger.warning("Generation failed; retrying (%d/%d)", attempt + 2, MAX_ATTEMPTS)
                pause(deadline)
        result = retry_step(lambda: download_image(url, directory, deadline), deadline)
        return {"outputs": [{"type": "image", "path": str(result)}]}
    except Exception as error:
        # No credential or provider traceback is returned to Glance task logs.
        raise RuntimeError(safe_error(error, key)) from None


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Remove described objects from one image")
    parser.add_argument("image", type=Path)
    parser.add_argument("--prompt", required=True)
    args = parser.parse_args()
    print(json.dumps(main({"input": {"path": str(args.image)}, "parameters": {"prompt": args.prompt}}), ensure_ascii=False))
