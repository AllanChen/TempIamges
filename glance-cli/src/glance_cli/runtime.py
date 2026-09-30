"""Prepare input, invoke main.py, and validate its structured output."""

import json
from contextlib import contextmanager
import mimetypes
import os
from pathlib import Path
import subprocess
import sys
import tempfile
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


def prepare_input(task: dict, temporary: Path) -> dict:
    task = dict(task)
    input_info = dict(task.get("input") or {})
    url = input_info.get("url")
    if url:
        parsed = urlparse(url)
        if parsed.scheme != "https":
            raise ValueError("任务输入必须是 HTTPS 地址")
        suffix = Path(parsed.path).suffix[:12]
        destination = temporary / f"input{suffix}"
        with urlopen(Request(url, headers={"User-Agent": USER_AGENT}), timeout=60) as response, destination.open("wb") as output:
            remaining = MAX_FILE
            while chunk := response.read(min(1024 * 1024, remaining + 1)):
                remaining -= len(chunk)
                if remaining < 0:
                    raise ValueError("输入文件超过 50 MB")
                output.write(chunk)
        input_info["path"] = str(destination)
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
            checked_output = {"type": kind, "path": str(path)}
            if kind == "image" and output.get("returnURL") is True:
                checked_output["returnURL"] = True
            checked.append(checked_output)
    return checked


@contextmanager
def execute(code_path: Path, task: dict, *, timeout: int = 1500,
            download_input: bool = True, python_path: str | Path | None = None):
    code_path = code_path.resolve(strict=True)
    if not (code_path / "main.py").is_file():
        raise ValueError(f"找不到 {code_path / 'main.py'}")
    with tempfile.TemporaryDirectory(prefix="glance-task-") as directory:
        temporary = Path(directory)
        prepared = prepare_input(task, temporary) if download_input else task
        task_path = temporary / "task.json"
        result_path = temporary / "result.json"
        task_path.write_text(json.dumps(prepared, ensure_ascii=False), encoding="utf-8")
        try:
            process = subprocess.run(
                [str(resolve_python(python_path)), str(Path(__file__).with_name("runner.py")), str(code_path),
                 str(task_path), str(result_path)], cwd=code_path,
                env={**os.environ, "GLANCE_TASK_OUTPUT_DIR": str(temporary)},
                capture_output=True, text=True, timeout=timeout, check=False)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"main.py 运行超过 {timeout} 秒") from error
        if process.returncode:
            raise RuntimeError(process.stderr.strip()[-4000:] or "main.py 执行失败")
        yield validate_outputs(json.loads(result_path.read_text(encoding="utf-8")), code_path)
