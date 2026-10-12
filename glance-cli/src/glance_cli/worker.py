"""One machine-wide worker with one batch pull request at a time."""

from collections import Counter
from concurrent.futures import ThreadPoolExecutor, Future
import json
import os
from pathlib import Path
import tempfile
import threading
import time
import traceback
from urllib.parse import urlparse

from .api import APIError, request, upload_task_file
from .registry import connect, eligible, rows, update, utc_now
from .result_spool import discard as discard_results, load as load_results, save as save_results
from .runtime import TaskCancelledError, execute
from .worker_logs import configure_worker_logging, logger


DEFAULT_MAX_CONCURRENT = 4
MAX_CONCURRENT_CEILING = 200
DEFAULT_PER_WIDGET_CONCURRENT = 1  # 0 means no per-widget limit.
PULL_WAIT = 5  # Short long-poll keeps registry edits visible within five seconds.
DELIVERY_ATTEMPTS = 4
HEARTBEAT_INTERVAL = 30
LOOP_ERROR_BACKOFF = 5


class DeliveryDeferredError(RuntimeError):
    """Keep the generated output so the next task claim can deliver it."""


def _read_int_env(name: str, default: int, minimum: int, maximum: int | None) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError:
        logger.warning("%s=%r 不是整数，使用默认值 %s", name, raw, default)
        return default
    clamped = max(minimum, value) if maximum is None else max(minimum, min(maximum, value))
    if clamped != value:
        logger.warning("%s=%s 超出允许范围，已调整为 %s", name, value, clamped)
    return clamped


def _concurrency_settings() -> tuple[int, int]:
    """Read concurrency limits from the environment at worker start.

    Returns ``(max_concurrent, per_widget_limit)``. ``per_widget_limit`` of 0
    means a single Widget may use every worker slot.
    """
    max_concurrent = _read_int_env("GLANCE_WORKER_MAX_CONCURRENT", DEFAULT_MAX_CONCURRENT,
                                   1, MAX_CONCURRENT_CEILING)
    per_widget = _read_int_env("GLANCE_WORKER_PER_WIDGET_CONCURRENT",
                               DEFAULT_PER_WIDGET_CONCURRENT, 0, None)
    return max_concurrent, per_widget


def _deliver(operation, label: str, task_log):
    for attempt in range(1, DELIVERY_ATTEMPTS + 1):
        try:
            return operation()
        except APIError as error:
            status = error.status
            if status is not None and 400 <= status < 500 and status not in (
                401, 403, 404, 408, 409, 429,
            ):
                raise
            if status in (401, 403, 404, 409):
                raise DeliveryDeferredError(
                    f"{label}无法使用当前任务凭证：{error}"
                ) from error
            if attempt == DELIVERY_ATTEMPTS:
                raise DeliveryDeferredError(
                    f"{label}连续 {attempt} 次失败：{error}"
                ) from error
            delay = min(2 ** attempt, 30)
            task_log(f"{label}失败（{attempt}/{DELIVERY_ATTEMPTS}）：{error}；{delay} 秒后重试")
            time.sleep(delay)
    raise AssertionError("unreachable")


def _sync_widget_status(db, widget_id: str) -> None:
    registered = [row for row in rows(db) if row["widget_id"] == widget_id
                  and row["server_status"] != "removed"]
    try:
        detail = request("GET", f"/api/v2/developer/widgets/{widget_id}")
    except APIError as error:
        if error.status == 404:
            for row in registered:
                update(db, widget_id, row["version"], server_status="removed", enabled=0)
            logger.warning("[%s] Widget 已删除或无权访问；已停止本机拉取", widget_id)
            return
        raise
    # Task routing is per Widget ID. A server-side version edit must not
    # disable the code already bound to this Widget on the developer's machine.
    for row in registered:
        update(db, widget_id, row["version"], server_status=detail["status"])


def _read_progress(path: Path) -> dict:
    """Read the widget's progress file; anything unusable means no progress."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        progress = data["progress"]
        if isinstance(progress, bool) or not isinstance(progress, (int, float)):
            return {}
        phase = data.get("phase", "")
        return {"progress": max(0, min(100, int(progress))),
                "phase": phase[:40] if isinstance(phase, str) else ""}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return {}


def _run_task(row: dict, task: dict) -> None:
    task_id = task["taskId"]
    claim = task["claimToken"]
    stopped = threading.Event()
    cancelled = threading.Event()
    progress_directory = tempfile.TemporaryDirectory(prefix="glance-progress-")
    progress_file = Path(progress_directory.name) / "progress.json"
    started = time.monotonic()

    def task_log(message: str) -> None:
        logger.info("[%s] %s", task_id, message)

    def heartbeat() -> None:
        while not stopped.wait(HEARTBEAT_INTERVAL):
            try:
                request("POST", f"/api/v2/widget-tasks/{task_id}/heartbeat",
                        _read_progress(progress_file), headers={"X-Task-Claim": claim})
            except APIError as error:
                if error.status in (404, 409):
                    task_log("任务已被取消/不再活动，停止执行")
                    cancelled.set()
                    return
                logger.warning("[%s] 心跳失败：%s", task_id, error)
            except Exception as error:
                logger.warning("[%s] 心跳异常：%s", task_id, error)

    def check_cancelled() -> None:
        if cancelled.is_set():
            raise TaskCancelledError("任务已被取消")

    thread = threading.Thread(target=heartbeat, daemon=True)
    thread.start()
    try:
        outputs = load_results(task_id)
        if outputs is None:
            with execute(Path(row["code_path"]), task, python_path=row["python_path"],
                         on_log=task_log, cancel_event=cancelled,
                         progress_file=progress_file) as generated:
                outputs = save_results(task_id, generated)
            task_log(f"已在本机保存 {len(outputs)} 个结果，等待服务端确认")
        else:
            task_log(f"复用本机已生成的 {len(outputs)} 个结果，跳过重复生成")
        artifacts = []
        for index, output in enumerate(outputs, start=1):
            check_cancelled()
            if output["type"] == "text":
                task_log(f"结果 {index}/{len(outputs)}：文本，{len(output['text'].encode())} 字节")
                artifacts.append(output)
            elif "url" in output:
                task_log(f"结果 {index}/{len(outputs)}：类型={output['type']}，远端来源={urlparse(output['url']).hostname}")
                artifacts.append({"type": output["type"], "url": output["url"]})
            else:
                path = Path(output["path"])
                task_log(f"上传结果 {index}/{len(outputs)}：类型={output['type']}，文件={path.name}，大小={path.stat().st_size} 字节")
                uploaded = _deliver(
                    lambda: upload_task_file(task_id, path, claim_token=claim),
                    f"结果 {index} 上传", task_log,
                )
                task_log(f"结果上传完成：assetID={uploaded['assetID']}，类型={uploaded.get('type', output['type'])}")
                artifacts.append({"type": output["type"], "assetID": uploaded["assetID"]})
        check_cancelled()
        task_log(f"回传任务结果：状态=succeeded，输出={len(artifacts)} 个")
        response = _deliver(
            lambda: request("POST", f"/api/v2/widget-tasks/{task_id}/result",
                            {"status": "succeeded", "artifacts": artifacts},
                            headers={"X-Task-Claim": claim}),
            "成功状态回报", task_log,
        )
        task_log(f"服务端确认：状态={response.get('status', 'unknown')}，taskID={response.get('taskID', task_id)}")
        discard_results(task_id)
        task_log(f"任务完成：输出={len(artifacts)} 个，总耗时={time.monotonic() - started:.1f} 秒")
    except TaskCancelledError:
        discard_results(task_id)
        task_log("任务已取消，已终止 Widget 进程并丢弃本机结果，不回传")
    except DeliveryDeferredError as error:
        logger.warning("[%s] 结果仍保存在本机；等待服务器重新分配任务后继续上传：%s",
                       task_id, error)
        raise
    except Exception as error:
        try:
            request("POST", f"/api/v2/widget-tasks/{task_id}/result",
                    {"status": "failed", "errorCode": "worker_error",
                     "message": str(error)[:1000], "artifacts": []}, headers={"X-Task-Claim": claim})
        except APIError as report_error:
            logger.error("[%s] 失败且无法回报：%s", task_id, report_error)
        logger.error("[%s] 失败：%s", task_id, error)
        raise
    finally:
        stopped.set()
        thread.join(timeout=1)
        progress_directory.cleanup()


def run_worker() -> None:
    configure_worker_logging()
    db = connect()
    active: dict[Future, tuple[str, str]] = {}
    last_sync = 0.0
    batch_offset = 0
    pull_failures = 0
    max_concurrent, per_widget_limit = _concurrency_settings()
    logger.info("Glance Worker 已启动；每次请求前读取本机 Widget 表。按 Ctrl+C 停止。")
    logger.info("并发上限：总计 %s 个任务，每个 Widget %s",
                max_concurrent, "不限" if per_widget_limit == 0 else f"{per_widget_limit} 个")
    try:
        with ThreadPoolExecutor(max_workers=max_concurrent) as pool:
            while True:
                try:
                    if time.monotonic() - last_sync > 60:
                        for widget_id in {row["widget_id"] for row in rows(db)
                                          if row["server_status"] not in ("local", "removed")}:
                            try:
                                _sync_widget_status(db, widget_id)
                            except APIError as error:
                                logger.warning("[%s] 状态同步失败：%s", widget_id, error)
                        last_sync = time.monotonic()
                    for future, key in list(active.items()):
                        if future.done():
                            active.pop(future)
                            try:
                                future.result()
                                update(db, *key, last_error=None)
                            except Exception as error:
                                update(db, *key, last_error=str(error)[:1000])
                    running = Counter(widget_id for widget_id, _ in active.values())
                    candidates = eligible(db, running, per_widget_limit)
                    if not candidates or len(active) >= max_concurrent:
                        time.sleep(1)
                        continue
                    if len(candidates) > 50:
                        start = batch_offset % len(candidates)
                        candidates = (candidates[start:] + candidates[:start])[:50]
                        batch_offset += 50
                    widgets = [{"widgetId": row["widget_id"]} for row in candidates]
                    logger.info("请求任务：%s 个 Widget，最长等待 %s 秒", len(widgets), PULL_WAIT)
                    try:
                        result = request("POST", "/api/v2/widget-tasks/pull-batch",
                                         {"widgets": widgets, "wait": PULL_WAIT},
                                         timeout=PULL_WAIT + 15)
                    except APIError as error:
                        pull_failures += 1
                        retry_delay = min(3 * 2 ** min(pull_failures - 1, 4), 30)
                        logger.warning("拉取失败：%s；%s 秒后重试", error, retry_delay)
                        time.sleep(retry_delay)
                        continue
                    pull_failures = 0
                    for row in candidates:
                        update(db, row["widget_id"], row["version"], last_request_at=utc_now())
                    task = result.get("task")
                    if not task:
                        logger.info("暂无任务，继续等待")
                        continue
                    row = next((item for item in candidates if item["widget_id"] == task["widgetId"]), None)
                    if row is None:
                        try:
                            request("POST", f"/api/v2/widget-tasks/{task['taskId']}/result",
                                    {"status": "failed", "errorCode": "widget_not_registered"},
                                    headers={"X-Task-Claim": task["claimToken"]})
                        except Exception as error:
                            logger.error("[%s] Widget 未注册且无法回报：%s", task["taskId"], error)
                        continue
                    logger.info("[%s] 执行 %s（本机代码 v%s）", task["taskId"], row["widget_id"], row["version"])
                    active[pool.submit(_run_task, row, task)] = (row["widget_id"], row["version"])
                except Exception:
                    logger.error("Worker 主循环异常，%s 秒后继续：\n%s",
                                 LOOP_ERROR_BACKOFF, traceback.format_exc())
                    time.sleep(LOOP_ERROR_BACKOFF)
    except KeyboardInterrupt:
        logger.info("正在等待运行中的任务结束…")
    finally:
        db.close()
