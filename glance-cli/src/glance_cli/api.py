"""Small JSON and multipart client for GlanceService."""

import json
import mimetypes
import os
from pathlib import Path
import uuid
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from . import __version__
from .registry import read_token


BASE_URL = os.environ.get("GLANCE_API_URL", "https://glance-service.allanchanni.workers.dev").rstrip("/")
USER_AGENT = f"glance-cli/{__version__}"


class APIError(RuntimeError):
    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


def _error_message(envelope: dict, fallback: str) -> str:
    error = envelope.get("error")
    if isinstance(error, dict) and isinstance(error.get("message"), str):
        return error["message"]
    return fallback


def request(method: str, path: str, body: dict | None = None, *,
            token: str | None = None, timeout: float = 35,
            headers: dict[str, str] | None = None,
            authenticated: bool = True) -> dict:
    if authenticated:
        token = token or read_token()
        if not token:
            raise APIError("请先运行 glance login，或配置 GLANCE_MOCK_TOKEN 测试 token")
    payload = json.dumps(body).encode() if body is not None else None
    headers = {"User-Agent": USER_AGENT,
               **({"Authorization": f"Bearer {token}"} if authenticated else {}),
               **(headers or {})}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    req = Request(BASE_URL + path, data=payload, headers=headers, method=method)
    try:
        with urlopen(req, timeout=timeout) as response:
            envelope = json.load(response)
    except HTTPError as error:
        try:
            detail = json.load(error)
            message = _error_message(detail, str(error)) if isinstance(detail, dict) else str(error)
        except (ValueError, OSError):
            message = str(error)
        raise APIError(message, error.code) from error
    except (URLError, TimeoutError, OSError, ValueError) as error:
        raise APIError(str(error)) from error
    if not isinstance(envelope, dict):
        raise APIError("Invalid API response")
    if not envelope.get("success"):
        raise APIError(_error_message(envelope, "API request failed"))
    result = envelope.get("result", {})
    if not isinstance(result, dict):
        raise APIError("Invalid API result")
    return result


def upload_task_file(task_id: str, path: Path, *, token: str | None = None,
                     claim_token: str) -> dict:
    token = token or read_token()
    if not token:
        raise APIError("请先运行 glance login，或配置 GLANCE_MOCK_TOKEN 测试 token")
    boundary = f"glance-{uuid.uuid4().hex}"
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    filename = path.name.replace('"', "_").replace("\r", "_").replace("\n", "_")
    prefix = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
              f"filename=\"{filename}\"\r\nContent-Type: {mime}\r\n\r\n").encode()
    payload = prefix + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    req = Request(f"{BASE_URL}/api/v2/widget-tasks/{task_id}/artifacts",
                  data=payload, method="POST", headers={
                      "Authorization": f"Bearer {token}",
                      "User-Agent": USER_AGENT,
                      "X-Task-Claim": claim_token,
                      "Content-Type": f"multipart/form-data; boundary={boundary}"})
    try:
        with urlopen(req, timeout=120) as response:
            envelope = json.load(response)
    except HTTPError as error:
        try:
            detail = json.load(error)
            message = _error_message(detail, str(error)) if isinstance(detail, dict) else str(error)
        except (ValueError, OSError):
            message = str(error)
        raise APIError(message, error.code) from error
    except (URLError, TimeoutError, OSError, ValueError) as error:
        raise APIError(str(error)) from error
    if not isinstance(envelope, dict):
        raise APIError("Invalid upload response")
    if not envelope.get("success"):
        raise APIError(_error_message(envelope, "Upload failed"))
    result = envelope.get("result")
    if not isinstance(result, dict) or not isinstance(result.get("assetID"), str):
        raise APIError("Invalid upload result")
    return result
