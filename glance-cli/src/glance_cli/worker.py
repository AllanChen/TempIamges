"""One machine-wide worker with one batch pull request at a time."""

from concurrent.futures import ThreadPoolExecutor, Future
from pathlib import Path
import threading
import time
from urllib.parse import urlparse

from .api import APIError, request, upload_task_file
from .registry import connect, eligible, rows, update, utc_now
from .result_spool import discard as discard_results, load as load_results, save as save_results
from .runtime import execute
from .worker_logs import configure_worker_logging, logger


MAX_CONCURRENT = 4
PULL_WAIT = 5  # Short long-poll keeps registry edits visible within five seconds.
DELIVERY_ATTEMPTS = 4


class DeliveryDeferredError(RuntimeError):
    """Keep the generated output so the next task claim can deliver it."""


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


def _run_task(row: dict, task: dict) -> None:
    task_id = task["taskId"]
    claim = task["claimToken"]
    stopped = threading.Event()
    started = time.monotonic()

    def task_log(message: str) -> None:
        logger.info("[%s] %s", task_id, message)

    def heartbeat() -> None:
        while not stopped.wait(30):
            try:
                request("POST", f"/api/v2/widget-tasks/{task_id}/heartbeat", {},
                        headers={"X-Task-Claim": claim})
            except APIError as error:
                logger.warning("[%s] 心跳失败：%s", task_id, error)

    thread = threading.Thread(target=heartbeat, daemon=True)
    thread.start()
    try:
        outputs = load_results(task_id)
        if outputs is None:
            with execute(Path(row["code_path"]), task, python_path=row["python_path"],
                         on_log=task_log) as generated:
                outputs = save_results(task_id, generated)
            task_log(f"已在本机保存 {len(outputs)} 个结果，等待服务端确认")
        else:
            task_log(f"复用本机已生成的 {len(outputs)} 个结果，跳过重复生成")
        artifacts = []
        for index, output in enumerate(outputs, start=1):
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


def run_worker() -> None:
    configure_worker_logging()
    db = connect()
    active: dict[Future, tuple[str, str]] = {}
    last_sync = 0.0
    batch_offset = 0
    pull_failures = 0
    logger.info("Glance Worker 已启动；每次请求前读取本机 Widget 表。按 Ctrl+C 停止。")
    try:
        with ThreadPoolExecutor(max_workers=MAX_CONCURRENT) as pool:
            while True:
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
                busy = {widget_id for widget_id, _ in active.values()}
                candidates = eligible(db, busy)
                if not candidates or len(active) >= MAX_CONCURRENT:
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
                    request("POST", f"/api/v2/widget-tasks/{task['taskId']}/result",
                            {"status": "failed", "errorCode": "widget_not_registered"},
                            headers={"X-Task-Claim": task["claimToken"]})
                    continue
                logger.info("[%s] 执行 %s（本机代码 v%s）", task["taskId"], row["widget_id"], row["version"])
                active[pool.submit(_run_task, row, task)] = (row["widget_id"], row["version"])
    except KeyboardInterrupt:
        logger.info("正在等待运行中的任务结束…")
    finally:
        db.close()
