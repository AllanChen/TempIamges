"""Remove video watermarks with RunningHub, processing clips of at most 8 seconds."""

import json
import logging
import math
import os
import shutil
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from uuid import uuid4


logger = logging.getLogger(__name__)

BASE_URL = "https://www.runninghub.ai"
UPLOAD_URL = f"{BASE_URL}/task/openapi/upload"
RUN_URL = f"{BASE_URL}/openapi/v2/run/ai-app/2098906395704819714"
QUERY_URL = f"{BASE_URL}/openapi/v2/query"
NODE_ID = "5099"
MAX_CLIP_SECONDS = 8.0
SPLIT_TARGET_SECONDS = 7.8  # Leave room for MP4 frame/audio packet rounding.
MAX_SEGMENTS = 24  # Glance runs one Widget for at most 25 minutes.
MAX_INPUT_BYTES = 50 * 1024 * 1024
MAX_UPLOAD_BYTES = 30 * 1024 * 1024
MAX_RESULT_BYTES = 50 * 1024 * 1024
TOTAL_TIMEOUT = 1350
POLL_TIMEOUT = 900
POLL_INTERVAL = 5
REQUEST_RETRIES = 3
GENERATION_ATTEMPTS = 3


class AuditRejectedError(RuntimeError):
    """An explicit content review rejection must not be retried."""


class GenerationFailedError(RuntimeError):
    """RunningHub confirmed that this attempt failed before producing a result."""


class SubmissionStateUnknownError(RuntimeError):
    """Do not repeat a potentially billed submission with an unknown task ID."""


def safe_error(value: object, api_key: str) -> str:
    return str(value).replace(api_key, "[REDACTED]")[:500]


def failed_reason(result: dict) -> dict:
    reason = result.get("failedReason") or {}
    if isinstance(reason, str):
        try:
            reason = json.loads(reason)
        except ValueError:
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
        reason.get("code", ""), result.get("errorCode", ""),
        result.get("errorMessage", ""), result.get("message", ""), result.get("msg", ""),
    )).lower()
    return any(term in detail for term in (
        "porn", "nsfw", "色情", "涉黄", "political", "politics", "涉政", "政治",
        "content_audit", "content review",
    ))


def provider_message(result: dict, api_key: str) -> str:
    reason = failed_reason(result)
    detail = (result.get("errorMessage") or reason.get("exception_message")
              or reason.get("message") or result.get("message") or result.get("msg")
              or result.get("status") or "Unknown provider error")
    return safe_error(detail, api_key)


def remaining(deadline: float) -> float:
    value = deadline - time.monotonic()
    if value <= 0:
        raise TimeoutError("Video watermark removal exceeded the Widget deadline")
    return value


def request_json(request: Request, operation: str, api_key: str, deadline: float,
                 *, retry_transient: bool = True) -> dict:
    attempts = REQUEST_RETRIES if retry_transient else 1
    for attempt in range(1, attempts + 1):
        try:
            with urlopen(request, timeout=min(60, remaining(deadline))) as response:
                try:
                    result = json.load(response)
                except ValueError as error:
                    if not retry_transient:
                        raise SubmissionStateUnknownError(
                            "RunningHub submit returned invalid JSON; task status is unknown"
                        ) from error
                    raise RuntimeError(f"RunningHub {operation} returned invalid JSON") from error
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
                raise RuntimeError(f"RunningHub {operation} authentication failed: HTTP {error.code}") from None
            if error.code not in (408, 429) and error.code < 500:
                raise RuntimeError(
                    f"RunningHub {operation} failed: HTTP {error.code}, {safe_error(detail, api_key)}"
                ) from None
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
        time.sleep(min(2 ** attempt, remaining(deadline)))
    raise AssertionError("unreachable")


def post_json(url: str, payload: dict, api_key: str, operation: str, deadline: float,
              *, retry_transient: bool = True) -> dict:
    request = Request(url, data=json.dumps(payload).encode("utf-8"),
                      headers={"Content-Type": "application/json",
                               "Authorization": f"Bearer {api_key}"}, method="POST")
    return request_json(request, operation, api_key, deadline,
                        retry_transient=retry_transient)


def run_media_tool(command: list[str], deadline: float, label: str) -> str:
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=min(180, remaining(deadline)), check=False)
    except subprocess.TimeoutExpired as error:
        raise TimeoutError(f"{label} timed out") from error
    if result.returncode:
        raise RuntimeError(f"{label} failed: {result.stderr[-1200:]}")
    return result.stdout


def probe_video(path: Path, deadline: float) -> tuple[float, int, int, bool]:
    result = run_media_tool(["ffprobe", "-v", "error", "-show_entries",
                             "format=duration:stream=codec_type,width,height", "-of", "json", str(path)],
                            deadline, "ffprobe")
    try:
        data = json.loads(result)
        duration = float(data["format"]["duration"])
        video = next(stream for stream in data["streams"] if stream["codec_type"] == "video")
        width, height = int(video["width"]), int(video["height"])
        audio = any(stream["codec_type"] == "audio" for stream in data["streams"])
    except (KeyError, ValueError, TypeError, StopIteration) as error:
        raise ValueError(f"Invalid video file: {path.name}") from error
    if not math.isfinite(duration) or duration <= 0 or width <= 0 or height <= 0:
        raise ValueError(f"Invalid video metadata: {path.name}")
    return duration, width, height, audio


def split_video(source: Path, directory: Path, deadline: float) -> list[Path]:
    duration, _, _, _ = probe_video(source, deadline)
    count = max(1, math.ceil(duration / (MAX_CLIP_SECONDS if duration <= MAX_CLIP_SECONDS
                                        else SPLIT_TARGET_SECONDS)))
    if count > MAX_SEGMENTS:
        raise ValueError(f"This video needs {count} clips; at most {MAX_SEGMENTS} clips fit one Widget task")
    clip_length = duration / count
    clips = []
    for index in range(count):
        destination = directory / f"input-{index:03d}.mp4"
        start = index * clip_length
        length = min(clip_length, duration - start)
        # Re-encode instead of copying at keyframes: every uploaded clip starts
        # at its intended frame and is independently decodable by RunningHub.
        run_media_tool([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
            "-ss", f"{start:.6f}", "-t", f"{length:.6f}",
            "-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libx264",
            "-preset", "veryfast", "-crf", "23", "-maxrate", "4M", "-bufsize", "8M",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
            "-ar", "48000", "-ac", "2", "-movflags", "+faststart", str(destination),
        ], deadline, f"split clip {index + 1}/{count}")
        clip_duration, _, _, _ = probe_video(destination, deadline)
        if clip_duration > MAX_CLIP_SECONDS + 0.01:
            raise RuntimeError(f"Clip {index + 1} exceeds the 8-second provider limit")
        if not 0 < destination.stat().st_size <= MAX_UPLOAD_BYTES:
            raise ValueError(f"Clip {index + 1} is empty or exceeds RunningHub's 30 MB upload limit")
        clips.append(destination)
    return clips


def upload_video(path: Path, api_key: str, deadline: float) -> str:
    if not 0 < path.stat().st_size <= MAX_UPLOAD_BYTES:
        raise ValueError("RunningHub video upload must be between 1 byte and 30 MB")
    boundary = f"glance-{uuid4().hex}"
    body = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="apiKey"\r\n\r\n'
        f"{api_key}\r\n"
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="fileType"\r\n\r\n'
        "input\r\n"
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="file"; filename="clip.mp4"\r\n'
        "Content-Type: video/mp4\r\n\r\n"
    ).encode("utf-8") + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode("ascii")
    request = Request(UPLOAD_URL, data=body,
                      headers={"Authorization": f"Bearer {api_key}",
                               "Content-Type": f"multipart/form-data; boundary={boundary}"},
                      method="POST")
    result = request_json(request, "upload", api_key, deadline)
    data = result.get("data") or {}
    name = (data.get("fileName") or data.get("filename")) if isinstance(data, dict) else None
    if result.get("code") not in (0, 200) or not isinstance(name, str) or not name:
        if is_audit_rejection(result):
            raise AuditRejectedError(f"RunningHub content rejected: {provider_message(result, api_key)}")
        raise RuntimeError(f"RunningHub video upload failed: {provider_message(result, api_key)}")
    return name


def submit_task(api_key: str, uploaded_name: str, deadline: float) -> str:
    result = post_json(RUN_URL, {
        "nodeInfoList": [{"nodeId": NODE_ID, "fieldName": "video",
                          "fieldValue": uploaded_name, "description": None}],
        "instanceType": "default", "usePersonalQueue": "false",
    }, api_key, "submit", deadline, retry_transient=False)
    task_id = result.get("taskId")
    if task_id:
        return str(task_id)
    if is_audit_rejection(result):
        raise AuditRejectedError(f"RunningHub content rejected: {provider_message(result, api_key)}")
    if str(result.get("errorCode")) in ("400", "401", "403", "422"):
        raise RuntimeError(f"RunningHub rejected the request: {provider_message(result, api_key)}")
    if result.get("errorCode") or result.get("errorMessage") or result.get("message"):
        raise GenerationFailedError(f"RunningHub did not accept the task: {provider_message(result, api_key)}")
    raise SubmissionStateUnknownError("RunningHub submit returned no task ID or failure reason")


def video_result_url(result: dict) -> str:
    entries = result.get("results")
    if not isinstance(entries, list):
        raise GenerationFailedError("RunningHub completed without video results")
    urls = [entry.get("url") for entry in entries if isinstance(entry, dict)]
    urls = [url for url in urls if isinstance(url, str)]
    preferred = next((url for url in urls if Path(urlparse(url).path).suffix.lower()
                      in (".mp4", ".mov", ".webm", ".mkv")), None)
    url = preferred or (urls[0] if urls else None)
    parsed = urlparse(url or "")
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.hostname.lower() in ("localhost", "127.0.0.1", "::1")):
        raise GenerationFailedError("RunningHub returned no valid HTTPS video URL")
    return url


def wait_for_result(api_key: str, task_id: str, deadline: float) -> str:
    poll_deadline = min(deadline, time.monotonic() + POLL_TIMEOUT)
    while remaining(poll_deadline) > 0:
        result = post_json(QUERY_URL, {"taskId": task_id}, api_key, "query", poll_deadline)
        status = result.get("status")
        if status == "SUCCESS":
            return video_result_url(result)
        if status in ("FAILED", "FAILURE", "ERROR"):
            if is_audit_rejection(result):
                raise AuditRejectedError(f"RunningHub content rejected: {provider_message(result, api_key)}")
            raise GenerationFailedError(f"RunningHub task failed: {provider_message(result, api_key)}")
        if status not in ("RUNNING", "QUEUED"):
            raise RuntimeError(f"RunningHub returned unknown task status: {safe_error(status, api_key)}")
        time.sleep(min(POLL_INTERVAL, remaining(poll_deadline)))
    raise AssertionError("unreachable")


def download_video(url: str, destination: Path, api_key: str, deadline: float) -> Path:
    for attempt in range(1, REQUEST_RETRIES + 1):
        complete = False
        try:
            with urlopen(Request(url, headers={"User-Agent": "Glance-Widget/1.0"}),
                         timeout=min(60, remaining(deadline))) as response:
                size = 0
                with destination.open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        size += len(chunk)
                        if size > MAX_RESULT_BYTES:
                            raise ValueError("A RunningHub video clip exceeds 50 MB")
                        output.write(chunk)
            if size == 0:
                raise ValueError("RunningHub returned an empty video clip")
            probe_video(destination, deadline)
            complete = True
            return destination
        except (HTTPError, URLError, TimeoutError) as error:
            retryable = not isinstance(error, HTTPError) or error.code in (408, 429) or error.code >= 500
            if not retryable or attempt == REQUEST_RETRIES:
                raise RuntimeError(f"RunningHub video download failed: {type(error).__name__}") from error
            logger.warning("RunningHub download attempt %d/%d failed; retrying", attempt, REQUEST_RETRIES)
            time.sleep(min(2 ** attempt, remaining(deadline)))
        finally:
            if not complete:
                destination.unlink(missing_ok=True)
    raise AssertionError("unreachable")


def process_clip(index: int, clip: Path, directory: Path, api_key: str,
                 deadline: float) -> tuple[int, Path]:
    uploaded_name = upload_video(clip, api_key, deadline)
    for attempt in range(1, GENERATION_ATTEMPTS + 1):
        remaining(deadline)
        try:
            task_id = submit_task(api_key, uploaded_name, deadline)
            logger.info("Clip %d: RunningHub task %s (attempt %d/%d)",
                        index + 1, task_id, attempt, GENERATION_ATTEMPTS)
            url = wait_for_result(api_key, task_id, deadline)
            break
        except GenerationFailedError:
            if attempt == GENERATION_ATTEMPTS or remaining(deadline) < 10:
                raise
            logger.warning("Clip %d generation failed; retrying %d/%d",
                           index + 1, attempt + 1, GENERATION_ATTEMPTS)
            time.sleep(min(5 * attempt, remaining(deadline)))
    destination = directory / f"result-{index:03d}.mp4"
    return index, download_video(url, destination, api_key, deadline)


def normalize_and_merge(results: list[Path], directory: Path, deadline: float) -> Path:
    _, width, height, _ = probe_video(results[0], deadline)
    width += width % 2
    height += height % 2
    normalized = []
    for index, source in enumerate(results):
        _, _, _, has_audio = probe_video(source, deadline)
        destination = directory / f"normalized-{index:03d}.mp4"
        command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source)]
        if not has_audio:
            command += ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"]
        command += [
            "-map", "0:v:0", "-map", "0:a:0" if has_audio else "1:a:0",
            "-vf", f"fps=30,scale={width}:{height}:force_original_aspect_ratio=decrease,"
                   f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "24",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
            "-ar", "48000", "-ac", "2", "-af", "aresample=async=1:first_pts=0,apad",
            "-shortest", "-movflags", "+faststart", str(destination),
        ]
        run_media_tool(command, deadline, f"normalize result {index + 1}/{len(results)}")
        probe_video(destination, deadline)
        normalized.append(destination)
    concat_file = directory / "ordered-clips.txt"
    concat_file.write_text("".join(f"file '{str(path).replace(chr(39), chr(39) + chr(92) + chr(39) + chr(39))}'\n"
                                   for path in normalized), encoding="utf-8")
    merged = directory / "result.mp4"
    run_media_tool(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat",
                    "-safe", "0", "-i", str(concat_file), "-c", "copy",
                    "-movflags", "+faststart", str(merged)], deadline, "merge clips")
    duration, _, _, _ = probe_video(merged, deadline)
    if not 0 < merged.stat().st_size <= MAX_RESULT_BYTES:
        # The Glance runtime accepts at most 50 MB for one uploaded media file.
        video_bitrate = int((MAX_RESULT_BYTES * 8 * 0.85) / duration) - 96_000
        if video_bitrate < 200_000:
            raise ValueError("Merged video is too long to fit Glance's 50 MB result limit")
        compact = directory / "result-compact.mp4"
        run_media_tool(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(merged),
                        "-c:v", "libx264", "-preset", "veryfast", "-b:v", str(video_bitrate),
                        "-maxrate", str(video_bitrate), "-bufsize", str(video_bitrate * 2),
                        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "96k",
                        "-movflags", "+faststart", str(compact)], deadline, "compress merged video")
        merged = compact
    if not 0 < merged.stat().st_size <= MAX_RESULT_BYTES:
        raise ValueError("Merged video exceeds Glance's 50 MB result limit")
    return merged


def main(task: dict) -> dict:
    input_path = (task.get("input") or {}).get("path")
    if not isinstance(input_path, str) or not input_path or not Path(input_path).is_file():
        raise ValueError("task.input.path must point to one existing video")
    source = Path(input_path)
    if not 0 < source.stat().st_size <= MAX_INPUT_BYTES:
        raise ValueError("The input video must be nonempty and at most 50 MB")
    api_key = os.environ.get("RUNNINGHUB_API_KEY_AI", "").strip()
    if not api_key:
        raise ValueError("RUNNINGHUB_API_KEY_AI is required")
    for program in ("ffmpeg", "ffprobe"):
        if shutil.which(program) is None:
            raise RuntimeError(f"{program} is required on the Widget Worker")
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or
                      tempfile.mkdtemp(prefix="glance-video-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + TOTAL_TIMEOUT
    clips = split_video(source, output_dir, deadline)
    logger.info("Video split into %d ordered clips (each at most 8 seconds)", len(clips))
    results: list[Path | None] = [None] * len(clips)
    with ThreadPoolExecutor(max_workers=min(3, len(clips))) as pool:
        futures = {pool.submit(process_clip, index, clip, output_dir, api_key, deadline): index
                   for index, clip in enumerate(clips)}
        try:
            for future in as_completed(futures):
                index, path = future.result()
                results[index] = path
                logger.info("Processed clip %d/%d", index + 1, len(clips))
        except BaseException:
            for future in futures:
                future.cancel()
            raise
    ordered = [path for path in results if path is not None]
    if len(ordered) != len(clips):
        raise RuntimeError("One or more video clips did not return a result")
    merged = normalize_and_merge(ordered, output_dir, deadline)
    return {"outputs": [{"type": "video", "path": str(merged)}]}
