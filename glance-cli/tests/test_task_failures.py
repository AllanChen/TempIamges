"""Worker failure recovery uses mocked transport; never charges real accounts."""

from contextlib import contextmanager
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from glance_cli.api import APIError, request, upload_task_file
from glance_cli.result_spool import load, load_failure, save, save_failure
from glance_cli.runtime import TaskCancelledError, TaskTimeoutError, execute, prepare_input, validate_outputs
from glance_cli.worker import DeliveryDeferredError, _deliver, _run_task


class TaskFailureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        environment = patch.dict(os.environ, {"GLANCE_CLI_HOME": str(self.root / "config")})
        environment.start()
        self.addCleanup(environment.stop)
        self.row = {"code_path": str(self.root), "python_path": sys.executable}
        self.task = {"taskId": "failure-test", "claimToken": "claim-one", "input": {}}
        self.failure = {"status": "failed", "errorCode": "worker_timeout",
                        "message": "execution timed out", "artifacts": []}

    def test_failed_execution_retries_report_without_claiming_success(self):
        with patch("glance_cli.worker.execute", side_effect=RuntimeError("provider rejected input")), \
             patch("glance_cli.worker.request", side_effect=[APIError("offline"), {"status": "failed"}]) as api, \
             patch("glance_cli.worker.time.sleep"):
            with self.assertRaisesRegex(RuntimeError, "provider rejected"):
                _run_task(self.row, self.task)
        self.assertEqual(api.call_count, 2)
        self.assertTrue(all(call.args[2]["status"] == "failed" for call in api.call_args_list))
        self.assertIsNone(load_failure(self.task["taskId"]))

    def test_failure_survives_network_loss_and_new_claim_without_reexecution(self):
        with patch("glance_cli.worker.execute", side_effect=TaskTimeoutError("timed out")), \
             patch("glance_cli.worker.request", side_effect=APIError("offline")) as api, \
             patch("glance_cli.worker.time.sleep"):
            with self.assertRaises(TaskTimeoutError):
                _run_task(self.row, self.task)
        self.assertEqual(api.call_count, 4)
        self.assertEqual(load_failure(self.task["taskId"])["errorCode"], "worker_timeout")
        with patch("glance_cli.worker.execute") as run, \
             patch("glance_cli.worker.request", return_value={"status": "failed"}) as api:
            _run_task(self.row, {**self.task, "claimToken": "claim-two"})
        run.assert_not_called()
        self.assertEqual(api.call_args.kwargs["headers"]["X-Task-Claim"], "claim-two")
        self.assertEqual(api.call_args.args[2]["status"], "failed")
        self.assertIsNone(load_failure(self.task["taskId"]))

    def test_failure_overrides_previously_spooled_success(self):
        save(self.task["taskId"], [{"type": "text", "text": "generated but rejected"}])
        save_failure(self.task["taskId"], self.failure)
        with patch("glance_cli.worker.execute") as run, \
             patch("glance_cli.worker.request", return_value={"status": "failed"}) as api:
            _run_task(self.row, self.task)
        run.assert_not_called()
        self.assertEqual(api.call_args.args[2], self.failure)
        self.assertIsNone(load(self.task["taskId"]))

    def test_failure_storage_error_still_reports_to_server(self):
        with patch("glance_cli.worker.execute", side_effect=RuntimeError("failed")), \
             patch("glance_cli.worker.save_failure", side_effect=OSError("disk full")), \
             patch("glance_cli.worker.request", return_value={"status": "failed"}) as api:
            with self.assertRaisesRegex(RuntimeError, "failed"):
                _run_task(self.row, self.task)
        self.assertEqual(api.call_args.args[2]["status"], "failed")

    def test_terminal_response_cleans_results_without_rerunning_or_failing_again(self):
        for status in ("completed", "failed", "expired", "cancelled"):
            with self.subTest(status=status):
                save(self.task["taskId"], [{"type": "text", "text": "ready"}])
                error = APIError("ended", 409, code="task_not_active", task_status=status)
                with patch("glance_cli.worker.execute") as run, \
                     patch("glance_cli.worker.request", side_effect=error) as api:
                    _run_task(self.row, self.task)
                run.assert_not_called()
                self.assertEqual(api.call_count, 1)
                self.assertIsNone(load(self.task["taskId"]))

    def test_ambiguous_or_expired_claim_keeps_results(self):
        for status, task_status in ((401, None), (404, None), (409, "running"), (409, "settled")):
            with self.subTest(status=status, task_status=task_status):
                save(self.task["taskId"], [{"type": "text", "text": "ready"}])
                error = APIError("claim invalid", status, code="task_not_active", task_status=task_status)
                with patch("glance_cli.worker.request", side_effect=error):
                    with self.assertRaises(DeliveryDeferredError):
                        _run_task(self.row, self.task)
                self.assertIsNotNone(load(self.task["taskId"]))
                self.assertIsNone(load_failure(self.task["taskId"]))

    def test_invalid_acknowledgement_keeps_result_for_reconciliation(self):
        save(self.task["taskId"], [{"type": "text", "text": "ready"}])
        with patch("glance_cli.worker.request", return_value={}), patch("glance_cli.worker.time.sleep"):
            with self.assertRaises(DeliveryDeferredError):
                _run_task(self.row, self.task)
        self.assertIsNotNone(load(self.task["taskId"]))
        self.assertIsNone(load_failure(self.task["taskId"]))

    def test_cancellation_during_delivery_stops_the_next_retry(self):
        event = threading.Event()
        calls = []

        def operation():
            calls.append(1)
            event.set()
            raise APIError("network failed")

        def check():
            if event.is_set():
                raise TaskCancelledError()

        with patch("glance_cli.worker.time.sleep"), self.assertRaises(TaskCancelledError):
            _deliver(operation, "upload", lambda _: None, check)
        self.assertEqual(len(calls), 1)

    def test_api_preserves_terminal_status_for_json_and_upload(self):
        media = self.root / "out.png"
        media.write_bytes(b"file")
        for call in (lambda: request("POST", "/result", {}, token="test"),
                     lambda: upload_task_file("task", media, token="test", claim_token="claim")):
            body = {"success": False, "status": "expired", "error": {"code": "task_not_active", "message": "ended"}}
            error = HTTPError("https://example.com", 409, "Conflict", {}, io.BytesIO(json.dumps(body).encode()))
            with patch("glance_cli.api._open", side_effect=error), self.assertRaises(APIError) as caught:
                call()
            self.assertEqual(caught.exception.task_status, "expired")
            self.assertEqual(caught.exception.code, "task_not_active")

    def test_empty_outputs_are_rejected(self):
        empty = self.root / "empty.png"
        empty.touch()
        for output in ({"type": "text", "text": " \n\t"}, {"type": "image", "path": str(empty)}):
            with self.subTest(output=output), self.assertRaises(ValueError):
                validate_outputs({"outputs": [output]}, self.root)

    def test_cancelled_or_expired_input_does_not_download(self):
        event = threading.Event()
        event.set()
        task = {"input": {"url": "https://example.com/input.png"}}
        with patch("glance_cli.runtime.urlopen") as network:
            with self.assertRaises(TaskCancelledError):
                prepare_input(task, self.root, cancel_event=event)
            with self.assertRaises(TaskTimeoutError):
                prepare_input(task, self.root, deadline=time.monotonic() - 1)
        network.assert_not_called()

    def test_input_download_checks_cancellation_between_chunks(self):
        event = threading.Event()

        class Response(io.BytesIO):
            def read(self, count):
                event.set()
                return super().read(count)

            read1 = read

        with patch("glance_cli.runtime.urlopen", return_value=Response(b"data")):
            with self.assertRaises(TaskCancelledError):
                prepare_input({"input": {"url": "https://example.com/input.png"}}, self.root, cancel_event=event)

    def test_input_time_counts_toward_execution_deadline(self):
        (self.root / "main.py").write_text("def main(task):\n    return {'outputs': []}\n")

        def slow_input(task, temporary, **kwargs):
            time.sleep(0.02)
            return task

        with patch("glance_cli.runtime.prepare_input", side_effect=slow_input), \
             patch("glance_cli.runtime.subprocess.Popen") as process:
            with self.assertRaises(TaskTimeoutError):
                with execute(self.root, {}, timeout=0.01):
                    self.fail("timeout must not produce a result")
        process.assert_not_called()

    def test_execution_timeout_reports_failure_and_stops_process(self):
        (self.root / "main.py").write_text("import time\ndef main(task):\n    time.sleep(30)\n")
        real_execute = execute

        @contextmanager
        def short_execution(*args, **kwargs):
            with real_execute(*args, **kwargs, timeout=0.1) as outputs:
                yield outputs

        started = time.monotonic()
        with patch("glance_cli.worker.execute", side_effect=short_execution), \
             patch("glance_cli.worker.request", return_value={"status": "failed"}) as api:
            with self.assertRaises(TaskTimeoutError):
                _run_task(self.row, self.task)
        self.assertLess(time.monotonic() - started, 5)
        self.assertEqual(api.call_args.args[2]["errorCode"], "worker_timeout")
        self.assertEqual(api.call_args.args[2]["status"], "failed")


if __name__ == "__main__":
    unittest.main()
