"""Remove video watermarks with the pppron vision-tasks API, in clips of at most 8 seconds.

The Worker splits the video, runs the clips with bounded concurrency, merges the
results with the original audio track, uploads the merged video to the pppron
temp bucket and returns its URL. Finished clips are cached per source file so a
re-run after a failure does not pay for them again.
"""

import datetime
import hashlib
import hmac
import json
import logging
import math
import os
import http.client
import shutil
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen
from uuid import uuid4


logger = logging.getLogger(__name__)
# Configuration for Cloudflare R2
ACCOUNT_ID = os.getenv('ACCOUNT_ID', 'a9507752bb0dde285fba2a464f8c6409')
ACCESS_KEY_ID = os.getenv('ACCESS_KEY_ID', '5096ea61f1aa248bb832f2acb7ffb59d')
SECRET_ACCESS_KEY = os.getenv('SECRET_ACCESS_KEY', '2125966a510d3ffc4fbd9c8111943378bfa83f69d281daa5e4b22ed3a7c4f174')

SUBMIT_URL = "https://api.pppron.com/vision-tasks"
STATUS_URL = "https://api.pppron.com/vision-tasks/uuid/{task_uuid}"
R2_BUCKET = "temp"
R2_PUBLIC_URL = "https://temp.pppron.com"
USER_AGENT = "Glance-Widget/1.0"
MAX_CLIP_SECONDS = 8.0
SPLIT_TARGET_SECONDS = 7.8  # Leave room for MP4 frame/audio packet rounding.
MAX_INPUT_BYTES = 100 * 1024 * 1024  # Matches the Glance upload limit.
MAX_RESULT_CLIP_BYTES = 50 * 1024 * 1024
CLIP_CONCURRENCY = max(1, int(os.environ.get("PPPRON_CONCURRENCY", "2") or 2))
CLIP_ATTEMPTS = 3
TOTAL_TIMEOUT = math.inf  # Video jobs can run for a long time; the Worker applies no limit either.
POLL_INTERVAL = 5
QUERY_TIMEOUT = 15
REQUEST_RETRIES = 6  # With backoff this rides out a network drop of about a minute.
MAX_BACKOFF = 20
TASK_STATUS_DONE = 3
TASK_STATUS_FAILED = 4
# Defaults from the reference script; each can come from a task parameter or a
# PPPRON_<NAME> Worker environment variable. The valid_token is a test token: replace it.
PARAMETER_DEFAULTS = {"valid_token": "8b4d2de5887d5d8b8cbb1862bcaff7f2", "team_id": 2, "team_creator_id": 1001, "user_id": 2001,
                      "widget_name": "4aac4fe1-55ac-49c0-8fba-c042ff815aee"}


class TaskFailedError(RuntimeError):
    """The provider finished a clip task with a failure status."""


def remaining(deadline: float) -> float:
    value = deadline - time.monotonic()
    if value <= 0:
        raise TimeoutError("Video processing exceeded the Widget deadline")
    return value


def fresh_request(request: Request) -> Request:
    """Copy a Request for one urlopen call.

    urllib mutates a Request when a proxy is configured (HTTPS_PROXY): after the
    first call its scheme becomes plain http, so reusing the same object sends
    later calls unencrypted through the proxy and Cloudflare answers 301.
    """
    headers = dict(request.header_items())
    headers.setdefault("User-agent", USER_AGENT)  # Cloudflare rejects urllib's default UA (1010).
    return Request(request.full_url, data=request.data, headers=headers, method=request.get_method())


def fetch(request: Request, operation: str, deadline: float, *, retry: bool = True,
          timeout: float = 60) -> bytes:
    attempts = REQUEST_RETRIES if retry else 1
    for attempt in range(1, attempts + 1):
        try:
            with urlopen(fresh_request(request), timeout=min(timeout, remaining(deadline))) as response:
                return response.read()
        except HTTPError as error:
            detail = error.read(512).decode("utf-8", errors="replace")
            if error.code not in (408, 429) and error.code < 500:
                raise RuntimeError(f"{operation} failed: HTTP {error.code} {detail}") from None
            failure = f"HTTP {error.code}"
        except (OSError, http.client.HTTPException) as error:
            # Includes URLError, timeouts and RemoteDisconnected (dropped connections).
            failure = type(error).__name__
        if attempt == attempts:
            raise RuntimeError(f"{operation} failed after {attempt} attempts: {failure}")
        logger.warning("%s attempt %d/%d failed (%s); retrying", operation, attempt, attempts, failure)
        time.sleep(min(2 ** attempt, MAX_BACKOFF, remaining(deadline)))
    raise AssertionError("unreachable")


def request_json(request: Request, operation: str, deadline: float, *, retry: bool = True,
                 timeout: float = 60) -> dict:
    try:
        result = json.loads(fetch(request, operation, deadline, retry=retry, timeout=timeout))
    except ValueError as error:
        raise RuntimeError(f"{operation} returned invalid JSON") from error
    if not isinstance(result, dict):
        raise RuntimeError(f"{operation} returned an invalid response")
    return result


def run_media_tool(command: list[str], deadline: float, label: str) -> str:
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=min(600, remaining(deadline)), check=False)
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
    clip_length = duration / count
    clips = []
    for index in range(count):
        destination = directory / f"input-{index:03d}.mp4"
        start = index * clip_length
        length = min(clip_length, duration - start)
        # Re-encode instead of copying at keyframes: every uploaded clip starts
        # at its intended frame and is independently decodable.
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
            raise RuntimeError(f"Clip {index + 1} exceeds the 8-second limit")
        if not 0 < destination.stat().st_size <= MAX_INPUT_BYTES:
            raise ValueError(f"Clip {index + 1} is empty or exceeds the upload limit")
        clips.append(destination)
    return clips


def signed_r2_put(account: str, key_id: str, secret: str, key: str, body: bytes) -> Request:
    """Build an AWS SigV4 PUT for the Cloudflare R2 S3 endpoint (no boto3 needed)."""
    host = f"{account}.r2.cloudflarestorage.com"
    uri = f"/{R2_BUCKET}/{quote(key)}"
    now = datetime.datetime.now(datetime.timezone.utc)
    stamp, date = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(body).hexdigest()
    signed_headers = "content-type;host;x-amz-content-sha256;x-amz-date"
    canonical = (f"PUT\n{uri}\n\ncontent-type:video/mp4\nhost:{host}\n"
                 f"x-amz-content-sha256:{payload_hash}\nx-amz-date:{stamp}\n\n"
                 f"{signed_headers}\n{payload_hash}")
    scope = f"{date}/auto/s3/aws4_request"
    to_sign = f"AWS4-HMAC-SHA256\n{stamp}\n{scope}\n{hashlib.sha256(canonical.encode()).hexdigest()}"
    signing_key = f"AWS4{secret}".encode()
    for part in (date, "auto", "s3", "aws4_request"):
        signing_key = hmac.new(signing_key, part.encode(), hashlib.sha256).digest()
    signature = hmac.new(signing_key, to_sign.encode(), hashlib.sha256).hexdigest()
    return Request(f"https://{host}{uri}", data=body, method="PUT", headers={
        "Content-Type": "video/mp4", "x-amz-content-sha256": payload_hash, "x-amz-date": stamp,
        "Authorization": f"AWS4-HMAC-SHA256 Credential={key_id}/{scope}, "
                         f"SignedHeaders={signed_headers}, Signature={signature}"})


def upload_video(path: Path, deadline: float) -> str:
    """Upload a video to the pppron temp R2 bucket and return its public URL."""
    credentials = (ACCOUNT_ID, ACCESS_KEY_ID, SECRET_ACCESS_KEY)
    if not all(credentials):
        raise ValueError("ACCOUNT_ID, ACCESS_KEY_ID and SECRET_ACCESS_KEY are required for R2 uploads")
    key = f"{uuid4()}_{path.name}"
    fetch(signed_r2_put(*credentials, key, path.read_bytes()), f"upload {path.name}", deadline)
    return f"{R2_PUBLIC_URL}/{key}"


def submit_task(base_payload: dict, clip_url: str, deadline: float) -> str:
    task_params = {**base_payload["task_params"], "url": clip_url}
    payload = {**base_payload, "task_params": task_params}
    request = Request(SUBMIT_URL, data=json.dumps(payload).encode("utf-8"), method="POST",
                      headers={"Content-Type": "application/json"})
    # A failed submit may still have created a billed task, so never retry it.
    result = request_json(request, "task submit", deadline, retry=False)
    inner = result.get("result")
    task_uuid = result.get("task_uuid") or (inner.get("task_uuid") if isinstance(inner, dict) else None)
    if not task_uuid:
        raise RuntimeError(f"Task submit returned no task_uuid: {json.dumps(result, ensure_ascii=False)[:300]}")
    return str(task_uuid)


def parse_task_result(value: object) -> dict:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
        except ValueError:
            return {"raw": value}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def wait_for_result(task_uuid: str, deadline: float) -> str:
    request = Request(STATUS_URL.format(task_uuid=task_uuid))
    while remaining(deadline) > 0:
        try:
            # One quick attempt per cycle: the loop itself is the retry, so a dead network
            # cannot burn the whole deadline inside a single query.
            data = request_json(request, "task query", deadline, retry=False, timeout=QUERY_TIMEOUT)
        except RuntimeError as error:
            logger.warning("Task %s query failed: %s", task_uuid, error)
            time.sleep(min(POLL_INTERVAL, remaining(deadline)))
            continue
        result = data.get("result") if data.get("success") else None
        status = result.get("task_status") if isinstance(result, dict) else None
        if status == TASK_STATUS_DONE:
            url = parse_task_result(result.get("task_result")).get("url")
            parsed = urlparse(url) if isinstance(url, str) else None
            if not parsed or parsed.scheme != "https" or not parsed.hostname:
                raise TaskFailedError(f"Task {task_uuid} completed without a valid HTTPS result URL")
            return url
        if status == TASK_STATUS_FAILED:
            detail = json.dumps(parse_task_result(result.get("task_result")), ensure_ascii=False)[:300]
            raise TaskFailedError(f"Task {task_uuid} failed: {detail}")
        time.sleep(min(POLL_INTERVAL, remaining(deadline)))
    raise AssertionError("unreachable")


def download_video(url: str, destination: Path, deadline: float) -> Path:
    for attempt in range(1, REQUEST_RETRIES + 1):
        complete = False
        try:
            with urlopen(Request(url, headers={"User-Agent": USER_AGENT}),
                         timeout=min(60, remaining(deadline))) as response:
                size = 0
                with destination.open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        size += len(chunk)
                        if size > MAX_RESULT_CLIP_BYTES:
                            raise ValueError("A result clip exceeds 50 MB")
                        output.write(chunk)
            if size == 0:
                raise ValueError("The provider returned an empty video clip")
            probe_video(destination, deadline)
            complete = True
            return destination
        except (OSError, http.client.HTTPException) as error:
            retryable = not isinstance(error, HTTPError) or error.code in (408, 429) or error.code >= 500
            if not retryable or attempt == REQUEST_RETRIES:
                raise RuntimeError(f"Result download failed: {type(error).__name__}") from error
            logger.warning("Result download attempt %d/%d failed; retrying", attempt, REQUEST_RETRIES)
            time.sleep(min(2 ** attempt, MAX_BACKOFF, remaining(deadline)))
        finally:
            if not complete:
                destination.unlink(missing_ok=True)
    raise AssertionError("unreachable")


class ClipCache:
    """Result URLs of finished clips, keyed by the source file so a re-run skips paid work."""

    def __init__(self, source: Path, count: int):
        root = Path(os.environ.get("GLANCE_VIDEO_WIDGET_CACHE") or Path.home() / ".cache" / "glance-video-widget")
        digest = hashlib.sha256()
        with source.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
        self.directory = root / digest.hexdigest()
        self.count = count

    def _path(self, index: int) -> Path:
        return self.directory / f"clip-{index:03d}-of-{self.count:03d}.json"

    def get(self, index: int) -> str | None:
        try:
            url = json.loads(self._path(index).read_text(encoding="utf-8")).get("url")
        except (OSError, ValueError, AttributeError):
            return None
        return url if isinstance(url, str) and url.startswith("https://") else None

    def put(self, index: int, url: str) -> None:
        try:
            self.directory.mkdir(parents=True, exist_ok=True)
            self._path(index).write_text(json.dumps({"url": url}), encoding="utf-8")
        except OSError as error:
            logger.warning("Could not cache clip %d result: %s", index + 1, error)


def process_clip(index: int, clip: Path, directory: Path, base_payload: dict,
                 cache: ClipCache, deadline: float) -> tuple[int, Path]:
    url = cache.get(index)
    if url:
        logger.warning("Clip %d: reusing cached result", index + 1)
    else:
        clip_url = upload_video(clip, deadline)
        for attempt in range(1, CLIP_ATTEMPTS + 1):
            task_uuid = submit_task(base_payload, clip_url, deadline)
            # Warning level so the task_uuid reaches the Worker log and a result can be recovered by hand.
            logger.warning("Clip %d: submitted task %s (attempt %d/%d)", index + 1, task_uuid, attempt, CLIP_ATTEMPTS)
            try:
                url = wait_for_result(task_uuid, deadline)
                break
            except TaskFailedError as error:
                # Only a confirmed provider failure is retried; an unknown submit
                # outcome is not, because it may already have been billed.
                if attempt == CLIP_ATTEMPTS:
                    raise
                logger.warning("Clip %d failed (%s); resubmitting", index + 1, error)
                time.sleep(min(5 * attempt, remaining(deadline)))
        cache.put(index, url)
    return index, download_video(url, directory / f"result-{index:03d}.mp4", deadline)


def normalize_and_merge(results: list[Path], directory: Path, deadline: float,
                        target_durations: list[float] | None = None) -> Path:
    """Re-encode every result clip to one format, retime it to the length of the
    clip that was submitted, and concatenate in order.

    A result that is noticeably longer or shorter than its input (frame-rate
    rounding, or a provider returning the wrong length) would desync the
    original audio; scaling the timestamps keeps every segment in place.
    """
    _, width, height, _ = probe_video(results[0], deadline)
    width += width % 2
    height += height % 2
    normalized = []
    for index, source in enumerate(results):
        clip_duration, _, _, has_audio = probe_video(source, deadline)
        target = target_durations[index] if target_durations else clip_duration
        ratio = target / clip_duration
        retime = abs(ratio - 1) > 0.02
        if retime:
            logger.warning("Result clip %d is %.2fs for a %.2fs input; retiming (×%.3f)",
                           index + 1, clip_duration, target, ratio)
        destination = directory / f"normalized-{index:03d}.mp4"
        command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source)]
        if not has_audio:
            command += ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"]
        command += [
            "-map", "0:v:0", "-map", "0:a:0" if has_audio else "1:a:0",
            "-vf", (f"setpts={ratio:.6f}*PTS," if retime else "") +
                   f"fps=30,scale={width}:{height}:force_original_aspect_ratio=decrease,"
                   f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "24",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
            "-ar", "48000", "-ac", "2", "-af", "aresample=async=1:first_pts=0,apad",
            # Cut audio at the exact video length; -shortest overshoots with apad
            # and the concat demuxer would then stretch every segment.
            "-t", f"{target:.3f}", "-movflags", "+faststart", str(destination),
        ]
        run_media_tool(command, deadline, f"normalize result {index + 1}/{len(results)}")
        probe_video(destination, deadline)
        normalized.append(destination)
    concat_file = directory / "ordered-clips.txt"
    # The concat demuxer resolves relative entries against the list file, so write absolute paths.
    concat_file.write_text("".join(f"file '{str(path.resolve()).replace(chr(39), chr(39) + chr(92) + chr(39) + chr(39))}'\n"
                                   for path in normalized), encoding="utf-8")
    merged = directory / "merged.mp4"
    run_media_tool(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat",
                    "-safe", "0", "-i", str(concat_file), "-c", "copy",
                    "-movflags", "+faststart", str(merged)], deadline, "merge clips")
    probe_video(merged, deadline)
    return merged


def restore_original_audio(merged: Path, source: Path, directory: Path, deadline: float) -> Path:
    """Replace the per-clip audio with the untouched audio track of the source video."""
    _, _, _, source_audio = probe_video(source, deadline)
    merged_duration, _, _, _ = probe_video(merged, deadline)
    destination = directory / "result.mp4"
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
               "-i", str(merged), "-i", str(source), "-map", "0:v:0"]
    if source_audio:
        command += ["-map", "1:a:0", "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-ac", "2"]
    # Trim to the video length explicitly: -shortest is unreliable with stream copy.
    command += ["-c:v", "copy", "-t", f"{merged_duration:.3f}", "-movflags", "+faststart", str(destination)]
    run_media_tool(command, deadline, "restore original audio")
    probe_video(destination, deadline)
    return destination


def build_payload(task: dict) -> dict:
    """Read the vision-tasks request fields from the Widget parameters."""
    parameters = task.get("task_params") or task.get("parameters") or {}
    if not isinstance(parameters, dict):
        raise ValueError("task parameters must be an object")
    values = {}
    for key, default in PARAMETER_DEFAULTS.items():
        value = parameters.get(key)
        if value in (None, ""):
            value = os.environ.get(f"PPPRON_{key.upper()}", "").strip() or default
        values[key] = int(value) if isinstance(default, int) else value
    extra = parameters.get("extra_params")
    task_params = dict(extra) if isinstance(extra, dict) else {}
    if parameters.get("prompt"):
        task_params["prompt"] = parameters["prompt"]
    return {**values, "task_type": parameters.get("task_type", 2), "task_execute_type": "seq",
            "task_status": 1, "with_logo": bool(parameters.get("with_logo", False)),
            "task_params": task_params}


def main(task: dict) -> dict:
    input_path = (task.get("input") or {}).get("path")
    if not isinstance(input_path, str) or not input_path or not Path(input_path).is_file():
        raise ValueError("task.input.path must point to one existing video")
    source = Path(input_path)
    if not 0 < source.stat().st_size <= MAX_INPUT_BYTES:
        raise ValueError("The input video must be nonempty and at most 100 MB")
    base_payload = build_payload(task)
    for program in ("ffmpeg", "ffprobe"):
        if shutil.which(program) is None:
            raise RuntimeError(f"{program} is required on the Widget Worker")
    output_dir = Path(os.environ.get("GLANCE_TASK_OUTPUT_DIR") or
                      tempfile.mkdtemp(prefix="glance-video-widget-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + TOTAL_TIMEOUT
    clips = split_video(source, output_dir, deadline)
    logger.warning("Video split into %d ordered clips (each at most 8 seconds)", len(clips))
    cache = ClipCache(source, len(clips))
    results: list[Path | None] = [None] * len(clips)
    with ThreadPoolExecutor(max_workers=min(CLIP_CONCURRENCY, len(clips))) as pool:
        futures = {pool.submit(process_clip, index, clip, output_dir, base_payload, cache, deadline): index
                   for index, clip in enumerate(clips)}
        try:
            for future in as_completed(futures):
                index, path = future.result()
                results[index] = path
                logger.warning("Processed clip %d/%d", index + 1, len(clips))
        except BaseException:
            for future in futures:
                future.cancel()
            raise
    ordered = [path for path in results if path is not None]
    if len(ordered) != len(clips):
        raise RuntimeError("One or more video clips did not return a result")
    targets = [probe_video(clip, deadline)[0] for clip in clips]
    merged = normalize_and_merge(ordered, output_dir, deadline, targets)
    result = restore_original_audio(merged, source, output_dir, deadline)
    # Return a URL instead of a file: the merged video is not limited to the
    # 50 MB Glance result size, and the client downloads it directly.
    result_url = upload_video(result, deadline)
    logger.warning("Merged result uploaded: %s", result_url)
    return {"outputs": [{"type": "video", "url": result_url}]}
