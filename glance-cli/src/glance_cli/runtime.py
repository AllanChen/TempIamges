"""Prepare input, invoke main.py, and validate its structured output."""

import json
from collections import deque
from contextlib import contextmanager
import ipaddress
import mimetypes
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import urlopen
from urllib.request import Request

from .api import USER_AGENT


SUPPORTED = {"text", "image", "video", "audio"}
MAX_FILE = 50 * 1024 * 1024


def resolve_python(value: str | Path | None = None) -> Path:
    """Keep a stable interpreter path for each widget version."""
    # Do not resolve symlinks: venv/bin/python often points at a base Python,
    # and launching the resolved target would leave the virtual environment.
    path = Path(os.path.abspath(os.path.expanduser(str(value or sys.executable))))
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError(f"Python 解释器不存在或无法执行：{path}")
    return path


def prepare_input(task: dict, temporary: Path,
                  on_log: Callable[[str], None] | None = None) -> dict:
    task = dict(task)
    input_info = dict(task.get("input") or {})
    url = input_info.get("url")
    if url:
        parsed = urlparse(url)
        if parsed.scheme != "https":
            raise ValueError("任务输入必须是 HTTPS 地址")
        suffix = Path(parsed.path).suffix[:12]
        destination = temporary / f"input{suffix}"
        started = time.monotonic()
        if on_log:
            on_log(f"下载输入图片：来源={parsed.hostname}，目标={destination.name}")
        try:
            with urlopen(Request(url, headers={"User-Agent": USER_AGENT}), timeout=60) as response, destination.open("wb") as output:
                remaining = MAX_FILE
                downloaded = 0
                next_report = 5 * 1024 * 1024
                while chunk := response.read(min(1024 * 1024, remaining + 1)):
                    remaining -= len(chunk)
                    if remaining < 0:
                        raise ValueError("输入文件超过 50 MB")
                    output.write(chunk)
                    downloaded += len(chunk)
                    if on_log and downloaded >= next_report:
                        on_log(f"输入图片下载进度：{downloaded / (1024 * 1024):.1f} MB")
                        next_report += 5 * 1024 * 1024
                if on_log:
                    on_log(f"输入图片下载完成：HTTP {response.status}，{downloaded} 字节，耗时 {time.monotonic() - started:.1f} 秒")
        except HTTPError as error:
            raise RuntimeError(f"输入图片下载失败：HTTP {error.code}，来源={parsed.hostname}") from None
        except (URLError, TimeoutError) as error:
            raise RuntimeError(f"输入图片下载失败：来源={parsed.hostname}，错误={type(error).__name__}") from None
        input_info["path"] = str(destination)
    elif on_log and input_info.get("path"):
        path = Path(input_info["path"])
        on_log(f"使用本地输入：{path.name}，{path.stat().st_size} 字节")
    task["input"] = input_info
    return task


def validate_outputs(result: dict, code_path: Path) -> list[dict]:
    outputs = result.get("outputs")
    if not isinstance(outputs, list) or not outputs:
        raise ValueError("main(task) 必须返回非空 outputs 数组")
    checked = []
    for output in outputs:
        if not isinstance(output, dict) or output.get("type") not in SUPPORTED:
            raise ValueError("输出类型必须是 text、image、video 或 audio")
        kind = output["type"]
        if kind == "text":
            if not isinstance(output.get("text"), str):
                raise ValueError("text 输出需要 text 字符串")
            if len(output["text"].encode()) > 1024 * 1024:
                raise ValueError("text 输出不能超过 1 MB")
            checked.append({"type": kind, "text": output["text"]})
        else:
            remote_url = output.get("url")
            if remote_url is not None:
                if output.get("path") is not None or not isinstance(remote_url, str):
                    raise ValueError(f"{kind} 输出只能提供 url 或 path 之一")
                parsed = urlparse(remote_url)
                host = (parsed.hostname or "").lower().rstrip(".")
                if (parsed.scheme != "https" or not host or parsed.username or parsed.password
                        or host == "localhost" or host.endswith((".localhost", ".local"))):
                    raise ValueError(f"{kind} 输出需要有效的公开 HTTPS URL")
                try:
                    address = ipaddress.ip_address(host)
                except ValueError:
                    address = None
                if address is not None or host.isdigit():
                    raise ValueError(f"{kind} 输出 URL 不能使用 IP 地址")
                checked.append({"type": kind, "url": remote_url})
                continue
            value = output.get("path")
            if not isinstance(value, str) or not value:
                raise ValueError(f"{kind} 输出需要文件 path")
            path = Path(value)
            if not path.is_absolute():
                path = code_path / path
            path = path.resolve(strict=True)
            if not path.is_file() or path.stat().st_size > MAX_FILE:
                raise ValueError(f"{kind} 输出文件不存在或超过 50 MB")
            mime = mimetypes.guess_type(path.name)[0] or ""
            if not mime.startswith(f"{kind}/"):
                raise ValueError(f"{kind} 输出文件格式与类型不符：{path.name}")
            checked.append({"type": kind, "path": str(path)})
    return checked


@contextmanager
def execute(code_path: Path, task: dict, *, timeout: int = 1500,
            download_input: bool = True, python_path: str | Path | None = None,
            on_log: Callable[[str], None] | None = None):
    code_path = code_path.resolve(strict=True)
    if not (code_path / "main.py").is_file():
        raise ValueError(f"找不到 {code_path / 'main.py'}")
    with tempfile.TemporaryDirectory(prefix="glance-task-") as directory:
        temporary = Path(directory)
        prepared = prepare_input(task, temporary, on_log=on_log) if download_input else task
        task_path = temporary / "task.json"
        result_path = temporary / "result.json"
        task_path.write_text(json.dumps(prepared, ensure_ascii=False), encoding="utf-8")
        command = [str(resolve_python(python_path)), str(Path(__file__).with_name("runner.py")),
                   str(code_path), str(task_path), str(result_path)]
        environment = {**os.environ, "GLANCE_TASK_OUTPUT_DIR": str(temporary)}
        if on_log is None:
            try:
                process = subprocess.run(command, cwd=code_path, env=environment,
                                         capture_output=True, text=True, timeout=timeout, check=False)
            except subprocess.TimeoutExpired as error:
                raise RuntimeError(f"main.py 运行超过 {timeout} 秒") from error
            if process.returncode:
                raise RuntimeError(process.stderr.strip()[-4000:] or "main.py 执行失败")
        else:
            on_log(f"启动 Widget 进程：{code_path.name}，Python={command[0]}")
            recent_lines: deque[str] = deque(maxlen=80)
            with subprocess.Popen(command, cwd=code_path, env=environment,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, bufsize=1) as process:
                def forward_output() -> None:
                    assert process.stdout is not None
                    for line in process.stdout:
                        message = line.rstrip("\r\n")
                        if message:
                            recent_lines.append(message[:2000])
                            on_log(f"Widget: {message[:2000]}")

                reader = threading.Thread(target=forward_output, daemon=True)
                reader.start()
                try:
                    returncode = process.wait(timeout=timeout)
                except subprocess.TimeoutExpired as error:
                    process.kill()
                    process.wait()
                    raise RuntimeError(f"main.py 运行超过 {timeout} 秒") from error
                finally:
                    reader.join(timeout=2)
            if returncode:
                raise RuntimeError("\n".join(recent_lines)[-4000:] or "main.py 执行失败")
            on_log("Widget 进程完成，开始校验输出")
        outputs = validate_outputs(json.loads(result_path.read_text(encoding="utf-8")), code_path)
        if on_log:
            on_log(f"输出校验通过：{len(outputs)} 个结果，类型={','.join(output['type'] for output in outputs)}")
        yield outputs
