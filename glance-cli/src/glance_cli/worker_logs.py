"""Persistent Worker log and its CLI reader."""

from collections import deque
import logging
from logging.handlers import RotatingFileHandler
import os
import time

from .registry import worker_log_path


logger = logging.getLogger("glance_cli.worker")


def configure_worker_logging() -> None:
    path = worker_log_path()
    logger.setLevel(logging.INFO)
    logger.propagate = False
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
        handler.close()
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s",
                                  datefmt="%Y-%m-%d %H:%M:%S")
    file_handler = RotatingFileHandler(path, maxBytes=5_000_000,
                                       backupCount=3, encoding="utf-8")
    if os.name == "posix":
        path.chmod(0o600)
    file_handler.setFormatter(formatter)
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)


def show_worker_logs(lines: int = 100, follow: bool = False) -> None:
    if lines < 0:
        raise ValueError("--lines 不能小于 0")
    path = worker_log_path()
    stream = None
    initial = True
    try:
        while True:
            if stream is None and path.is_file():
                stream = path.open("r", encoding="utf-8", errors="replace")
                if initial:
                    for line in deque(stream, maxlen=lines):
                        print(line, end="", flush=True)
                    initial = False
            if not follow:
                if stream is None:
                    print("暂无 Worker 日志；启动 glance worker 后会生成日志。")
                return
            if stream is None:
                if initial:
                    print("等待 Worker 日志；按 Ctrl+C 退出。", flush=True)
                    initial = False
            else:
                line = stream.readline()
                if line:
                    print(line, end="", flush=True)
                    continue
                try:
                    current = path.stat()
                except FileNotFoundError:
                    current = None
                if (current is None or current.st_ino != os.fstat(stream.fileno()).st_ino
                        or current.st_size < stream.tell()):
                    stream.close()
                    stream = None
            time.sleep(0.5)
    except KeyboardInterrupt:
        return
    finally:
        if stream is not None:
            stream.close()
