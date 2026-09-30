"""Route image URLs to Freeimage or Glance R2 according to task location."""

import argparse
import ipaddress
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import uuid


UPLOAD_URL = "https://freeimage.host/api/1/upload"
MAX_IMAGE_BYTES = 50 * 1024 * 1024


def image_provider(url: str) -> str | None:
    parsed = urlparse(image_url(url))
    host = (parsed.hostname or "").lower()
    if host in {"iili.io", "freeimage.host"} or host.endswith((".iili.io", ".freeimage.host")):
        return "freeimage"
    if host.endswith(".r2.dev") or (host == "glance-service.allanchanni.workers.dev"
                                    and parsed.path.startswith("/api/v2/assets/")):
        return "r2"
    return None


def image_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("需要有效的 HTTP 或 HTTPS 图片 URL")
    host = parsed.hostname.lower()
    if host == "localhost" or host.endswith(".localhost"):
        raise ValueError("图片 URL 不能指向本机")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        if not address.is_global:
            raise ValueError("图片 URL 不能指向内网地址")
    return value


def read_image(stream) -> bytes:
    chunks = []
    size = 0
    while chunk := stream.read(min(1024 * 1024, MAX_IMAGE_BYTES - size + 1)):
        size += len(chunk)
        if size > MAX_IMAGE_BYTES:
            raise ValueError("图片超过 50 MB")
        chunks.append(chunk)
    if not size:
        raise ValueError("图片内容为空")
    return b"".join(chunks)


def detect_image(data: bytes) -> tuple[str, str]:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", "png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", "jpg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif", "gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp", "webp"
    if data.startswith(b"BM"):
        return "image/bmp", "bmp"
    if data[4:8] == b"ftyp" and data[8:12] in {b"heic", b"heix", b"hevc", b"heif", b"mif1", b"msf1"}:
        return "image/heic", "heic"
    raise ValueError("仅支持 PNG、JPEG、GIF、WebP、BMP 和 HEIC 图片")


def compatible_image(data: bytes) -> tuple[bytes, str, str]:
    mime, extension = detect_image(data)
    if mime != "image/heic":
        return data, mime, extension
    if not shutil.which("sips"):
        raise ValueError("HEIC 转换需要 macOS 的 sips 命令")
    with tempfile.TemporaryDirectory(prefix="glance-freeimage-") as directory:
        source = Path(directory) / "source.heic"
        output = Path(directory) / "source.png"
        source.write_bytes(data)
        process = subprocess.run(["sips", "-s", "format", "png", "--out", str(output), str(source)],
                                 capture_output=True, text=True, check=False)
        if process.returncode or not output.is_file():
            raise RuntimeError(f"HEIC 转换失败：{process.stderr.strip()}")
        converted = output.read_bytes()
    if len(converted) > MAX_IMAGE_BYTES:
        raise ValueError("转换后的图片超过 50 MB")
    return converted, "image/png", "png"


def download_image(url: str) -> bytes:
    request = Request(image_url(url), headers={"User-Agent": "glance-widget/1.0"})
    try:
        with urlopen(request, timeout=60) as response:
            return read_image(response)
    except (HTTPError, URLError) as error:
        raise RuntimeError(f"下载图片失败：{error}") from error


def upload_image(key: str, data: bytes, mime: str, extension: str) -> str:
    boundary = f"FreeimageBoundary-{uuid.uuid4().hex}"
    fields = (("key", key), ("action", "upload"), ("format", "json"))
    body = bytearray()
    for name, value in fields:
        body.extend(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode())
    body.extend((f"--{boundary}\r\nContent-Disposition: form-data; name=\"source\"; "
                 f"filename=\"widget-input.{extension}\"\r\nContent-Type: {mime}\r\n\r\n").encode())
    body.extend(data)
    body.extend(f"\r\n--{boundary}--\r\n".encode())
    request = Request(UPLOAD_URL, data=bytes(body), method="POST",
                      headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    try:
        with urlopen(request, timeout=120) as response:
            payload = json.load(response)
    except (HTTPError, URLError) as error:
        raise RuntimeError(f"Freeimage 上传失败：{error}") from error
    except ValueError as error:
        raise RuntimeError("Freeimage 返回了无效 JSON") from error
    if not isinstance(payload, dict) or payload.get("status_code") != 200:
        raise RuntimeError("Freeimage 上传失败：API 未返回成功状态")
    result = payload.get("image")
    uploaded_url = result.get("url") if isinstance(result, dict) else None
    if not isinstance(uploaded_url, str):
        raise RuntimeError("Freeimage 没有返回图片 URL")
    parsed = urlparse(uploaded_url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or not (host == "iili.io" or host.endswith(".iili.io") or host == "freeimage.host"):
        raise RuntimeError("Freeimage 返回了非预期的图片 URL")
    return uploaded_url


def r2_output(data: bytes, extension: str) -> dict:
    output_dir = os.environ.get("GLANCE_TASK_OUTPUT_DIR")
    if not output_dir:
        raise RuntimeError("上传 R2 需要通过 glance worker 执行任务")
    path = Path(output_dir) / f"uploaded-image.{extension}"
    path.write_bytes(data)
    return {"outputs": [{"type": "image", "path": str(path), "returnURL": True}]}


def main(task: dict | str) -> dict:
    """Reuse a matching provider URL, otherwise upload to the target provider."""
    if isinstance(task, str):
        task = {"input": {"url": task}, "parameters": {"location": "China"}}
    if not isinstance(task, dict):
        raise ValueError("task 必须是对象或图片 URL")
    input_info = task.get("input") or {}
    parameters = task.get("task_params") or task.get("parameters") or {}
    china = str(parameters.get("location") or task.get("location") or "").strip().upper() in {"CN", "CHINA"}
    target = "freeimage" if china else "r2"
    url = parameters.get("url") or input_info.get("url")
    if url and image_provider(url) == target:
        return {"outputs": [{"type": "text", "text": url}]}
    local_path = input_info.get("path")
    if local_path and (not parameters.get("url") or parameters.get("url") == input_info.get("url")):
        with Path(local_path).open("rb") as source:
            data = read_image(source)
    elif url:
        data = download_image(url)
    else:
        raise ValueError("请提供 input.url、parameters.url 或 input.path")
    data, mime, extension = compatible_image(data)
    if china:
        key = os.environ.get("FREEIMAGEKEY", "").strip()
        if key:
            try:
                uploaded_url = upload_image(key, data, mime, extension)
                return {"outputs": [{"type": "text", "text": uploaded_url}]}
            except RuntimeError:
                pass  # Freeimage 不可用时交给 Worker 上传 R2。
    return r2_output(data, extension)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upload an image URL to Freeimage")
    parser.add_argument("url", help="需要上传的图片 URL")
    arguments = parser.parse_args()
    print(json.dumps(main(arguments.url), ensure_ascii=False))
