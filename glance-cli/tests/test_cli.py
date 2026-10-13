import json
from contextlib import closing, contextmanager, redirect_stdout
import io
from urllib.error import HTTPError, URLError
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import venv

from glance_cli.cli import main, validate
from glance_cli.api import APIError, request, upload_task_file
from glance_cli.registry import connect, eligible, read_session, read_token, rows, update, upsert
from glance_cli.runtime import TaskCancelledError, execute, prepare_input, validate_outputs
from glance_cli.result_spool import load as load_results
import glance_cli
from glance_cli.worker import (DeliveryDeferredError, _concurrency_settings, _read_progress,
                               _run_task, _sync_widget_status, run_worker)
from glance_cli.worker_logs import configure_worker_logging, logger


class CLITest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        patcher = patch.dict(os.environ, {"GLANCE_CLI_HOME": str(self.root / "config"),
                                          "GLANCE_MOCK_TOKEN": "",
                                          # Tests mock urlopen; keep the direct-first path out of them.
                                          "GLANCE_API_DIRECT": "0"})
        patcher.start()
        self.addCleanup(patcher.stop)

    def create_widget(self):
        self.assertEqual(main(["widget", "init", "--directory", str(self.root)]), 0)
        widget = next(path for path in self.root.iterdir() if path.name != "config")
        return widget, json.loads((widget / "widget.json").read_text())

    def test_list_explains_empty_registry_without_changing_json_output(self):
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["widget", "list"]), 0)
        self.assertIn("本机尚未挂载 Widget", output.getvalue())
        self.assertIn("glance widget add", output.getvalue())

        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["widget", "list", "--json"]), 0)
        self.assertEqual(json.loads(output.getvalue()), [])

        _, manifest = self.create_widget()
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["widget", "list"]), 0)
        self.assertIn(manifest["id"], output.getvalue())
        self.assertNotIn("本机尚未挂载 Widget", output.getvalue())

    def test_init_creates_uuid_folder_and_local_row(self):
        folder, manifest = self.create_widget()
        self.assertEqual(folder.name, manifest["id"])
        self.assertTrue((folder / "main.py").is_file())
        with closing(connect()) as db:
            saved = rows(db)
            self.assertEqual(len(saved), 1)
            self.assertEqual(saved[0]["server_status"], "local")
            self.assertEqual(eligible(db, {}), [])
            update(db, manifest["id"], manifest["version"],
                   server_status="manual_review", enabled=1)
            self.assertEqual(len(eligible(db, {})), 1)
            self.assertEqual(eligible(db, {manifest["id"]: 1}), [])

    def test_result_url_preference_requires_media_output(self):
        _, manifest = self.create_widget()
        command = manifest["commands"][0]
        command["outputs"] = ["image"]
        command["showResultURL"] = True
        validate(manifest)
        command["outputs"] = ["video"]
        validate(manifest)
        command["outputs"] = ["text"]
        with self.assertRaisesRegex(ValueError, "只有图片或视频输出"):
            validate(manifest)
        command["showResultURL"] = "true"
        with self.assertRaisesRegex(ValueError, "必须是布尔值"):
            validate(manifest)

    def test_worker_stops_polling_widget_removed_from_server(self):
        folder, manifest = self.create_widget()
        with closing(connect()) as db:
            update(db, manifest["id"], manifest["version"],
                   server_status="published", enabled=1)
            upsert(db, widget_id=manifest["id"], version="0.2.0",
                   manifest_path=str(folder / "widget.json"), code_path=str(folder),
                   enabled=True, server_status="published")
            with patch("glance_cli.worker.request", side_effect=APIError("Widget not found.", 404)):
                _sync_widget_status(db, manifest["id"])
            self.assertEqual(eligible(db, {}), [])
            self.assertEqual({row["server_status"] for row in rows(db)}, {"removed"})
            self.assertTrue(all(row["enabled"] == 0 for row in rows(db)))

    def test_worker_keeps_widget_binding_when_server_version_changes(self):
        folder, manifest = self.create_widget()
        with closing(connect()) as db:
            update(db, manifest["id"], manifest["version"],
                   server_status="published", enabled=1)
            upsert(db, widget_id=manifest["id"], version="0.2.0",
                   manifest_path=str(folder / "widget.json"), code_path=str(folder),
                   enabled=True, server_status="published")
            detail = {"status": "published", "versions": [
                {"version": "0.2.0", "status": "published"}]}
            with patch("glance_cli.worker.request", return_value=detail):
                _sync_widget_status(db, manifest["id"])
            self.assertEqual([(row["version"], row["server_status"], row["enabled"])
                              for row in rows(db)],
                             [(manifest["version"], "published", 1), ("0.2.0", "published", 1)])
            self.assertEqual([row["version"] for row in eligible(db, {})], ["0.2.0"])
            self.assertEqual(eligible(db, {manifest["id"]: 1}), [])

    def test_worker_uses_newest_numeric_local_version_for_a_widget(self):
        folder, manifest = self.create_widget()
        with closing(connect()) as db:
            update(db, manifest["id"], manifest["version"],
                   server_status="published", enabled=1)
            for version in ("0.1.9", "0.1.10"):
                upsert(db, widget_id=manifest["id"], version=version,
                       manifest_path=str(folder / "widget.json"), code_path=str(folder),
                       enabled=True, server_status="published")
            self.assertEqual([row["version"] for row in eligible(db, {})], ["0.1.10"])

    def test_local_main_runs_and_validates_output(self):
        folder, manifest = self.create_widget()
        task = {"taskId": "local", "widgetId": manifest["id"],
                "version": manifest["version"], "commandId": "run", "input": {}, "parameters": {}}
        with execute(folder, task, download_input=False) as outputs:
            self.assertEqual(outputs, [{"type": "text", "text": "Hello from Glance"}])
        (folder / "main.py").write_text(
            'def main(task):\n    return {"outputs": [{"type": "audio", "path": "missing.mp3"}]}\n')
        with self.assertRaises(FileNotFoundError):
            with execute(folder, task, download_input=False):
                pass

    def test_worker_receives_widget_output_while_result_is_validated(self):
        folder, manifest = self.create_widget()
        (folder / "main.py").write_text(
            "import sys\n"
            "def main(task):\n"
            "    print('upload started', flush=True)\n"
            "    print('query completed', file=sys.stderr, flush=True)\n"
            "    return {'outputs': [{'type': 'text', 'text': 'done'}]}\n")
        task = {"taskId": "task_log", "widgetId": manifest["id"],
                "version": manifest["version"], "commandId": "run", "input": {}, "parameters": {}}
        messages = []
        with execute(folder, task, download_input=False, on_log=messages.append) as outputs:
            self.assertEqual(outputs, [{"type": "text", "text": "done"}])
        self.assertTrue(any("Widget: upload started" in message for message in messages))
        self.assertTrue(any("Widget: query completed" in message for message in messages))
        self.assertTrue(any("输出校验通过" in message for message in messages))

    def test_worker_keeps_widget_error_in_live_logs(self):
        folder, manifest = self.create_widget()
        (folder / "main.py").write_text(
            "def main(task):\n"
            "    print('before failure', flush=True)\n"
            "    raise RuntimeError('provider failed')\n")
        task = {"taskId": "task_error", "widgetId": manifest["id"],
                "version": manifest["version"], "commandId": "run", "input": {}, "parameters": {}}
        messages = []
        with self.assertRaisesRegex(RuntimeError, "provider failed"):
            with execute(folder, task, download_input=False, on_log=messages.append):
                pass
        self.assertTrue(any("Widget: before failure" in message for message in messages))
        self.assertTrue(any("provider failed" in message for message in messages))

    def test_input_download_logs_progress_without_signed_query(self):
        class FakeResponse(io.BytesIO):
            status = 200

        messages = []
        task = {"input": {"url": "https://example.com/input.png?sig=private"}}
        with patch("glance_cli.runtime.urlopen", return_value=FakeResponse(b"image")):
            prepared = prepare_input(task, self.root, on_log=messages.append)
        self.assertEqual(Path(prepared["input"]["path"]).read_bytes(), b"image")
        self.assertTrue(any("输入图片下载完成" in message for message in messages))
        self.assertNotIn("sig=private", "\n".join(messages))

    def test_multiple_media_inputs_are_downloaded_in_order(self):
        class FakeResponse(io.BytesIO):
            status = 200

        for kind, suffix in (("images", ".png"), ("videos", ".mp4")):
            with self.subTest(kind=kind):
                urls = [f"https://example.com/first{suffix}",
                        f"https://example.com/second{suffix}?sig=private"]
                calls = []

                def fake_urlopen(request, timeout):
                    calls.append(request.full_url)
                    return FakeResponse(request.full_url.encode())

                with patch("glance_cli.runtime.urlopen", side_effect=fake_urlopen):
                    prepared = prepare_input({"input": {"url": urls[0], kind: urls}}, self.root)
                paths = prepared["input"]["imagePaths" if kind == "images" else "videoPaths"]
                self.assertEqual(len(paths), 2)
                self.assertEqual(prepared["input"]["path"], paths[0])
                self.assertEqual([Path(path).read_bytes().decode() for path in paths], urls)
                self.assertEqual(calls, urls)

    def test_image_file_upload_keeps_its_media_type(self):
        widget = self.root / "widget"
        widget.mkdir()
        image = widget / "result.png"
        image.write_bytes(b"\x89PNG\r\n\x1a\n")
        outputs = validate_outputs({"outputs": [{"type": "image", "path": str(image)}]}, widget)
        self.assertEqual(outputs[0]["type"], "image")

        @contextmanager
        def fake_execute(*args, **kwargs):
            yield outputs

        task = {"taskId": "task_1", "claimToken": "claim_1"}
        with patch("glance_cli.worker.execute", side_effect=fake_execute), \
             patch("glance_cli.worker.upload_task_file", return_value={"assetID": "asset_1"}), \
             patch("glance_cli.worker.request") as api:
            _run_task({"code_path": str(widget), "python_path": sys.executable}, task)
        result_call = next(call for call in api.call_args_list if call.args[1].endswith("/result"))
        self.assertEqual(result_call.args[2]["artifacts"],
                         [{"type": "image", "assetID": "asset_1"}])

    def test_temporary_upload_failure_retries_without_failing_the_task(self):
        widget = self.root / "widget"
        widget.mkdir()
        image = widget / "result.png"
        image.write_bytes(b"\x89PNG\r\n\x1a\n")
        outputs = validate_outputs({"outputs": [{"type": "image", "path": str(image)}]}, widget)

        @contextmanager
        def fake_execute(*args, **kwargs):
            yield outputs

        task = {"taskId": "task_retry", "claimToken": "claim_1"}
        with patch("glance_cli.worker.execute", side_effect=fake_execute), \
             patch("glance_cli.worker.upload_task_file",
                   side_effect=[APIError("Broken pipe"), {"assetID": "asset_1"}]) as upload, \
             patch("glance_cli.worker.request") as api, \
             patch("glance_cli.worker.time.sleep"):
            _run_task({"code_path": str(widget), "python_path": sys.executable}, task)
        self.assertEqual(upload.call_count, 2)
        result_calls = [call for call in api.call_args_list if call.args[1].endswith("/result")]
        self.assertEqual(len(result_calls), 1)
        self.assertEqual(result_calls[0].args[2]["status"], "succeeded")

    def test_generated_image_survives_exhausted_upload_retries_and_new_claim(self):
        widget = self.root / "widget"
        widget.mkdir()
        image = widget / "result.png"
        image.write_bytes(b"\x89PNG\r\n\x1a\n")
        outputs = validate_outputs({"outputs": [{"type": "image", "path": str(image)}]}, widget)

        @contextmanager
        def fake_execute(*args, **kwargs):
            yield outputs

        task = {"taskId": "task_resume", "claimToken": "claim_1"}
        with patch("glance_cli.worker.execute", side_effect=fake_execute) as execute_widget, \
             patch("glance_cli.worker.upload_task_file", side_effect=APIError("Broken pipe")) as upload, \
             patch("glance_cli.worker.request") as api, \
             patch("glance_cli.worker.time.sleep"):
            with self.assertRaises(DeliveryDeferredError):
                _run_task({"code_path": str(widget), "python_path": sys.executable}, task)
        execute_widget.assert_called_once()
        self.assertEqual(upload.call_count, 4)
        self.assertFalse(any(call.args[1].endswith("/result") for call in api.call_args_list))
        stored = load_results("task_resume")
        self.assertEqual(len(stored), 1)
        self.assertEqual(Path(stored[0]["path"]).read_bytes(), image.read_bytes())

        image.unlink()
        next_claim = {"taskId": "task_resume", "claimToken": "claim_2"}
        with patch("glance_cli.worker.execute", side_effect=AssertionError("Widget ran twice")) as execute_widget, \
             patch("glance_cli.worker.upload_task_file", return_value={"assetID": "asset_1"}) as upload, \
             patch("glance_cli.worker.request", return_value={"status": "succeeded"}) as api:
            _run_task({"code_path": str(widget), "python_path": sys.executable}, next_claim)
        execute_widget.assert_not_called()
        self.assertEqual(upload.call_args.kwargs["claim_token"], "claim_2")
        self.assertEqual(load_results("task_resume"), None)
        result_call = next(call for call in api.call_args_list if call.args[1].endswith("/result"))
        self.assertEqual(result_call.args[2]["artifacts"],
                         [{"type": "image", "assetID": "asset_1"}])

    def test_success_report_retries_without_marking_generated_output_failed(self):
        widget = self.root / "widget"
        widget.mkdir()
        image = widget / "result.png"
        image.write_bytes(b"\x89PNG\r\n\x1a\n")
        outputs = validate_outputs({"outputs": [{"type": "image", "path": str(image)}]}, widget)

        @contextmanager
        def fake_execute(*args, **kwargs):
            yield outputs

        task = {"taskId": "task_report", "claimToken": "claim_1"}
        with patch("glance_cli.worker.execute", side_effect=fake_execute), \
             patch("glance_cli.worker.upload_task_file", return_value={"assetID": "asset_1"}), \
             patch("glance_cli.worker.request",
                   side_effect=[APIError("SSL EOF"), {"status": "succeeded"}]) as api, \
             patch("glance_cli.worker.time.sleep"):
            _run_task({"code_path": str(widget), "python_path": sys.executable}, task)
        self.assertEqual(api.call_count, 2)
        self.assertTrue(all(call.args[2]["status"] == "succeeded"
                            for call in api.call_args_list))
        self.assertEqual(load_results("task_report"), None)

    def test_image_url_is_passed_through_as_image_result(self):
        widget = self.root / "widget"
        widget.mkdir()
        url = "https://iili.io/result.png?token=private"
        outputs = validate_outputs({"outputs": [{"type": "image", "url": url}]}, widget)
        self.assertEqual(outputs, [{"type": "image", "url": url}])

        @contextmanager
        def fake_execute(*args, **kwargs):
            yield outputs

        task = {"taskId": "task_1", "claimToken": "claim_1"}
        with patch("glance_cli.worker.execute", side_effect=fake_execute), \
             patch("glance_cli.worker.upload_task_file") as upload, \
             patch("glance_cli.worker.request") as api:
            _run_task({"code_path": str(widget), "python_path": sys.executable}, task)
        upload.assert_not_called()
        result_call = next(call for call in api.call_args_list if call.args[1].endswith("/result"))
        self.assertEqual(result_call.args[2]["artifacts"], [{"type": "image", "url": url}])

    def test_media_url_rejects_private_address(self):
        with self.assertRaisesRegex(ValueError, "IP 地址"):
            validate_outputs({"outputs": [{"type": "image", "url": "https://127.0.0.1/result.png"}]}, self.root)

    def test_widget_uses_its_own_virtual_environment(self):
        folder, manifest = self.create_widget()
        environment = folder / ".venv"
        venv.EnvBuilder(with_pip=False).create(environment)
        python = environment / "bin" / "python"
        site_packages = Path(subprocess.check_output(
            [str(python), "-c", "import sysconfig; print(sysconfig.get_path('purelib'))"],
            text=True).strip())
        (site_packages / "widget_only_dependency.py").write_text("VALUE = 'from widget venv'\n")
        (folder / "main.py").write_text(
            "from widget_only_dependency import VALUE\n"
            "def main(task):\n"
            "    return {'outputs': [{'type': 'text', 'text': VALUE}]}\n")
        task = {"taskId": "local", "widgetId": manifest["id"],
                "version": manifest["version"], "commandId": "run", "input": {}, "parameters": {}}
        with execute(folder, task, download_input=False, python_path=python) as outputs:
            self.assertEqual(outputs[0]["text"], "from widget venv")
        self.assertEqual(main(["widget", "test", "--manifest", str(folder / "widget.json"),
                               "--python", str(python)]), 0)
        with closing(connect()) as db:
            update(db, manifest["id"], manifest["version"], python_path=str(python))
            self.assertEqual(rows(db)[0]["python_path"], str(python))

    def test_existing_registry_is_migrated(self):
        config = self.root / "config"
        config.mkdir()
        legacy = sqlite3.connect(config / "widgets.sqlite")
        legacy.execute("""CREATE TABLE widgets (
            widget_id TEXT NOT NULL, version TEXT NOT NULL,
            manifest_path TEXT NOT NULL, code_path TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 0, server_status TEXT NOT NULL DEFAULT 'local',
            submission_id TEXT, last_request_at TEXT, last_error TEXT,
            updated_at TEXT NOT NULL, PRIMARY KEY(widget_id, version))""")
        legacy.execute("""INSERT INTO widgets
            (widget_id, version, manifest_path, code_path, updated_at)
            VALUES ('old-widget', '1.0.0', '/old/widget.json', '/old', '2026-01-01')""")
        legacy.commit()
        legacy.close()
        with closing(connect()) as db:
            saved = rows(db)
            self.assertEqual(saved[0]["widget_id"], "old-widget")
            self.assertEqual(saved[0]["python_path"], sys.executable)

    def test_mock_login_saves_local_session(self):
        with patch.dict(os.environ, {"GLANCE_MOCK_TOKEN": "temporary-test-token"}):
            self.assertEqual(main(["login"]), 0)
        session = read_session()
        self.assertEqual(session["token"], "temporary-test-token")
        self.assertEqual(session["email"], "mock@glance.local")

    def test_test_token_works_without_login_for_add_requests_and_uploads(self):
        folder, manifest = self.create_widget()
        detail = {"status": "published", "versions": [
            {"version": manifest["version"], "status": "published"}]}
        with patch.dict(os.environ, {"GLANCE_MOCK_TOKEN": "temporary-test-token"}), \
             patch("glance_cli.cli.request", return_value=detail):
            self.assertEqual(main(["widget", "add", str(folder)]), 0)
            self.assertEqual(read_token(), "temporary-test-token")
            with patch("glance_cli.api.urlopen", return_value=io.BytesIO(
                    b'{"success":true,"result":{}}')) as opener:
                self.assertEqual(request("GET", "/api/v2/developer/auth/me"), {})
                self.assertEqual(opener.call_args.args[0].get_header("Authorization"),
                                 "Bearer temporary-test-token")
            artifact = self.root / "output.txt"
            artifact.write_text("test", encoding="utf-8")
            with patch("glance_cli.api.urlopen", side_effect=OSError("Broken pipe")):
                with self.assertRaisesRegex(APIError, "Broken pipe"):
                    upload_task_file("task-1", artifact, claim_token="claim-1")
            with patch("glance_cli.api.urlopen", return_value=io.BytesIO(
                    b'{"success":true,"result":{"assetID":"test-asset"}}')) as opener:
                self.assertEqual(upload_task_file("task-1", artifact, claim_token="claim-1"),
                                 {"assetID": "test-asset"})
                self.assertEqual(opener.call_args.args[0].get_header("Authorization"),
                                 "Bearer temporary-test-token")
        with closing(connect()) as db:
            self.assertEqual(rows(db)[0]["server_status"], "published")
            self.assertEqual(rows(db)[0]["enabled"], 1)
        self.assertFalse((self.root / "config" / "session.json").exists())

    def test_test_token_file_works_without_login(self):
        config = self.root / "config"
        config.mkdir()
        (config / "mock-token").write_text(" file-test-token\n", encoding="utf-8")
        self.assertEqual(read_token(), "file-test-token")
        self.assertFalse((config / "session.json").exists())

    def test_add_shared_directory_offline_and_readd_preserves_state(self):
        folder, manifest = self.create_widget()
        shared = self.root / "shared-widget"
        shutil.copytree(folder, shared)
        with closing(connect()) as db:
            db.execute("DELETE FROM widgets")
            db.commit()
        self.assertEqual(main(["widget", "add", str(shared)]), 0)
        with closing(connect()) as db:
            saved = rows(db)[0]
            self.assertEqual(saved["code_path"], str(shared.resolve()))
            self.assertEqual(saved["widget_id"], manifest["id"])
            self.assertEqual(saved["server_status"], "local")
            self.assertEqual(saved["enabled"], 0)
            update(db, manifest["id"], manifest["version"],
                   server_status="published", enabled=1)
        self.assertEqual(main(["widget", "add", str(folder)]), 0)
        with closing(connect()) as db:
            saved = rows(db)[0]
            self.assertEqual(saved["code_path"], str(folder.resolve()))
            self.assertEqual(saved["server_status"], "published")
            self.assertEqual(saved["enabled"], 1)

    def test_add_syncs_authorized_widget_and_disables_denied_widget(self):
        folder, manifest = self.create_widget()
        detail = {"status": "published", "versions": [
            {"version": "9.9.9", "status": "published"}]}
        with patch("glance_cli.cli.read_token", return_value="test"), \
             patch("glance_cli.cli.request", return_value=detail):
            self.assertEqual(main(["widget", "add", str(folder)]), 0)
        with closing(connect()) as db:
            self.assertEqual(rows(db)[0]["server_status"], "published")
            self.assertEqual(rows(db)[0]["enabled"], 1)
        with patch("glance_cli.cli.read_token", return_value="test"), \
             patch("glance_cli.cli.request", side_effect=APIError("Widget not found", 404)):
            self.assertEqual(main(["widget", "add", str(folder)]), 0)
        with closing(connect()) as db:
            self.assertEqual(rows(db)[0]["server_status"], "local")
            self.assertEqual(rows(db)[0]["enabled"], 0)

    def test_add_missing_code_stays_disabled(self):
        folder, manifest = self.create_widget()
        with closing(connect()) as db:
            update(db, manifest["id"], manifest["version"],
                   server_status="published", enabled=1)
        (folder / "main.py").unlink()
        self.assertEqual(main(["widget", "add", str(folder)]), 0)
        with closing(connect()) as db:
            saved = rows(db)[0]
            self.assertEqual(saved["server_status"], "local")
            self.assertEqual(saved["enabled"], 0)

    def test_add_uuid_caches_public_manifest_outside_widget_directory(self):
        folder, manifest = self.create_widget()
        shutil.rmtree(folder)
        previous = Path.cwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, previous)
        with patch("glance_cli.cli.request", return_value=manifest) as remote:
            self.assertEqual(main(["widget", "add", manifest["id"]]), 0)
        remote.assert_called_once_with("GET", f"/api/v2/widgets/{manifest['id']}",
                                       authenticated=False)
        self.assertFalse((folder / "widget.json").exists())
        self.assertFalse((folder / "main.py").exists())
        with closing(connect()) as db:
            saved = rows(db)[0]
            self.assertEqual(saved["enabled"], 0)
            self.assertEqual(json.loads(Path(saved["manifest_path"]).read_text()), manifest)
            self.assertEqual(Path(saved["manifest_path"]).parent,
                             self.root / "config" / "manifests")
        with patch("glance_cli.cli.request", side_effect=APIError("Service unavailable", 503)):
            self.assertEqual(main(["widget", "add", manifest["id"]]), 0)
        (folder / "main.py").write_text(
            "def main(task):\n"
            "    return {'outputs': [{'type': 'text', 'text': task['version']}]}\n")
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["widget", "test", "--code", str(folder)]), 0)
        self.assertIn(manifest["version"], output.getvalue())
        newer = {**manifest, "version": "0.2.0"}
        (folder / "widget.json").write_text(json.dumps(newer))
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["widget", "test", "--code", str(folder)]), 0)
        self.assertIn("0.2.0", output.getvalue())
        with patch("glance_cli.cli.request", side_effect=AssertionError("unexpected public lookup")):
            self.assertEqual(main(["widget", "add", manifest["id"]]), 0)
        with closing(connect()) as db:
            added = next(row for row in rows(db) if row["version"] == "0.2.0")
            self.assertEqual(added["code_path"], str(folder.resolve()))
            self.assertEqual(added["manifest_path"], str((folder / "widget.json").resolve()))

    def test_add_local_uuid_prefers_local_manifest_without_public_lookup(self):
        folder, manifest = self.create_widget()
        previous = Path.cwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, previous)
        with patch("glance_cli.cli.request", side_effect=AssertionError("unexpected public lookup")):
            self.assertEqual(main(["widget", "add", manifest["id"]]), 0)
        with closing(connect()) as db:
            self.assertEqual(rows(db)[0]["manifest_path"], str(folder.resolve() / "widget.json"))

    def test_worker_logs_show_recent_lines(self):
        configure_worker_logging()
        def close_logs():
            for handler in logger.handlers[:]:
                logger.removeHandler(handler)
                handler.close()
        self.addCleanup(close_logs)
        logger.info("first task")
        logger.info("second task")
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["worker", "logs", "--lines", "1"]), 0)
        self.assertIn("second task", output.getvalue())
        self.assertNotIn("first task", output.getvalue())
        self.assertTrue((self.root / "config" / "worker.log").is_file())

    def _sleeping_widget(self, grandchild_pid_file=None):
        folder, manifest = self.create_widget()
        spawn = ""
        if grandchild_pid_file:
            spawn = (
                "import subprocess, sys\n"
                "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
                f"open({str(grandchild_pid_file)!r}, 'w').write(str(child.pid))\n")
        (folder / "main.py").write_text(
            "import time\n" + spawn + "def main(task):\n    time.sleep(60)\n")
        return folder

    def _wait_gone(self, pid, seconds=3):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return True
            time.sleep(0.05)
        return False

    @unittest.skipUnless(os.name == "posix", "process groups are POSIX only")
    def test_heartbeat_409_kills_widget_and_grandchild_without_posting_result(self):
        pid_file = self.root / "grandchild.pid"
        folder = self._sleeping_widget(pid_file)
        heartbeats = []

        def fake_request(method, path, body=None, **kwargs):
            if path.endswith("/heartbeat"):
                heartbeats.append(body)
                if len(heartbeats) >= 2:
                    raise APIError("not active", 409)
            return {}

        task = {"taskId": "task_cancel", "claimToken": "claim_1", "input": {}}
        started = time.monotonic()
        with patch("glance_cli.worker.HEARTBEAT_INTERVAL", 0.2), \
             patch("glance_cli.worker.request", side_effect=fake_request) as api, \
             patch("glance_cli.worker.discard_results") as discard:
            _run_task({"code_path": str(folder), "python_path": sys.executable}, task)
        self.assertLess(time.monotonic() - started, 5)
        self.assertFalse([call for call in api.call_args_list if call.args[1].endswith("/result")])
        discard.assert_called_with("task_cancel")
        grandchild = int(pid_file.read_text())
        self.assertTrue(self._wait_gone(grandchild))

    def test_execute_without_on_log_is_cancellable(self):
        folder = self._sleeping_widget()
        cancel = threading.Event()
        threading.Timer(0.3, cancel.set).start()
        started = time.monotonic()
        with self.assertRaises(TaskCancelledError):
            with execute(folder, {"input": {}}, download_input=False, cancel_event=cancel):
                pass
        self.assertLess(time.monotonic() - started, 4)

    def test_report_progress_reaches_next_heartbeat_body(self):
        folder, manifest = self.create_widget()
        (folder / "main.py").write_text(
            "import time\n"
            "from glance_cli import report_progress\n"
            "def main(task):\n"
            "    report_progress(42, 'processing' + 'x' * 60)\n"
            "    time.sleep(1)\n"
            "    return {'outputs': [{'type': 'text', 'text': 'ok'}]}\n")
        bodies = []

        def fake_request(method, path, body=None, **kwargs):
            if path.endswith("/heartbeat"):
                bodies.append(body)
            return {"status": "succeeded"}

        task = {"taskId": "task_progress", "claimToken": "claim_1", "input": {}}
        source = str(Path(glance_cli.__file__).parent.parent)
        with patch.dict(os.environ, {"PYTHONPATH": source}), \
             patch("glance_cli.worker.HEARTBEAT_INTERVAL", 0.3), \
             patch("glance_cli.worker.request", side_effect=fake_request):
            _run_task({"code_path": str(folder), "python_path": sys.executable}, task)
        reported = [body for body in bodies if body.get("progress") == 42]
        self.assertTrue(reported, bodies)
        self.assertEqual(len(reported[0]["phase"]), 40)
        self.assertTrue(reported[0]["phase"].startswith("processing"))

    def test_report_progress_clamps_and_ignores_missing_environment(self):
        target = self.root / "progress.json"
        glance_cli.report_progress(5, "no env")
        self.assertFalse(target.exists())
        with patch.dict(os.environ, {"GLANCE_TASK_PROGRESS_FILE": str(target)}):
            glance_cli.report_progress(250, "x")
        self.assertEqual(json.loads(target.read_text()), {"progress": 100, "phase": "x"})
        target.write_text("not json")
        self.assertEqual(_read_progress(target), {})
        self.assertEqual(_read_progress(self.root / "missing.json"), {})

    def test_unregistered_widget_report_failure_does_not_stop_worker(self):
        with closing(connect()) as db:
            upsert(db, widget_id="known", version="1.0.0",
                   manifest_path=str(self.root / "widget.json"), code_path=str(self.root),
                   enabled=True, server_status="published")
        pulls = []

        def fake_request(method, path, body=None, **kwargs):
            if path.endswith("/pull-batch"):
                pulls.append(1)
                if len(pulls) == 1:
                    return {"task": {"taskId": "t1", "widgetId": "other", "claimToken": "c"}}
                if len(pulls) == 2:
                    raise ValueError("unexpected")
                raise KeyboardInterrupt
            raise APIError("report failed", 500)

        def close_logs():
            for handler in logger.handlers[:]:
                logger.removeHandler(handler)
                handler.close()
        self.addCleanup(close_logs)
        with patch("glance_cli.worker.request", side_effect=fake_request), \
             patch("glance_cli.worker.time.sleep") as sleep:
            run_worker()
        self.assertEqual(len(pulls), 3)
        sleep.assert_any_call(5)

    def test_eligible_filters_by_running_count_and_per_widget_limit(self):
        _, manifest = self.create_widget()
        with closing(connect()) as db:
            update(db, manifest["id"], manifest["version"],
                   server_status="published", enabled=1)
            widget_id = manifest["id"]
            self.assertEqual(len(eligible(db, {})), 1)
            self.assertEqual(eligible(db, {widget_id: 1}), [])  # default limit 1
            self.assertEqual(len(eligible(db, {widget_id: 2}, 3)), 1)
            self.assertEqual(eligible(db, {widget_id: 3}, 3), [])
            self.assertEqual(len(eligible(db, {widget_id: 50}, 0)), 1)  # 0 = unlimited

    def test_concurrency_settings_read_environment_with_defaults_and_clamping(self):
        cases = [
            ({}, (4, 1)),
            ({"GLANCE_WORKER_MAX_CONCURRENT": "3",
              "GLANCE_WORKER_PER_WIDGET_CONCURRENT": "3"}, (3, 3)),
            ({"GLANCE_WORKER_MAX_CONCURRENT": "0"}, (1, 1)),
            ({"GLANCE_WORKER_MAX_CONCURRENT": "999"}, (200, 1)),
            ({"GLANCE_WORKER_MAX_CONCURRENT": "abc",
              "GLANCE_WORKER_PER_WIDGET_CONCURRENT": "-2"}, (4, 0)),
            ({"GLANCE_WORKER_PER_WIDGET_CONCURRENT": "0"}, (4, 0)),
        ]
        for environment, expected in cases:
            with self.subTest(environment=environment), \
                 patch.dict(os.environ, environment, clear=False):
                for name in ("GLANCE_WORKER_MAX_CONCURRENT", "GLANCE_WORKER_PER_WIDGET_CONCURRENT"):
                    if name not in environment:
                        os.environ.pop(name, None)
                self.assertEqual(_concurrency_settings(), expected)

    def _run_worker_for_one_widget(self, environment: dict, expected_parallel: int):
        """Pull tasks for one Widget until ``expected_parallel`` run at once.

        Fake tasks block on a gate that opens only once the worker has had to
        wait, so the peak concurrency is deterministic. Returns
        ``(pull_count_at_first_wait, peak_concurrency, total_tasks)``.
        """
        with closing(connect()) as db:
            upsert(db, widget_id="w", version="1.0.0",
                   manifest_path=str(self.root / "widget.json"), code_path=str(self.root),
                   enabled=True, server_status="published")
        gate = threading.Event()
        lock = threading.Lock()
        state = {"started": 0, "running": 0, "peak": 0, "pulls": 0, "first_wait": None}

        def fake_request(method, path, body=None, **kwargs):
            if path.endswith("/pull-batch"):
                state["pulls"] += 1
                if state["pulls"] > expected_parallel + 1:
                    raise KeyboardInterrupt
                return {"task": {"taskId": f"t{state['pulls']}", "widgetId": "w", "claimToken": "c"}}
            return {"status": "published"}

        def fake_run_task(row, task):
            with lock:
                state["started"] += 1
                state["running"] += 1
                state["peak"] = max(state["peak"], state["running"])
            gate.wait(timeout=10)
            with lock:
                state["running"] -= 1

        def fake_sleep(seconds):
            if state["first_wait"] is None:
                state["first_wait"] = state["pulls"]
            with lock:
                ready = state["started"] >= expected_parallel
            if ready:
                gate.set()

        def close_logs():
            for handler in logger.handlers[:]:
                logger.removeHandler(handler)
                handler.close()
        self.addCleanup(close_logs)
        with patch.dict(os.environ, environment), \
             patch("glance_cli.worker.request", side_effect=fake_request), \
             patch("glance_cli.worker._run_task", side_effect=fake_run_task), \
             patch("glance_cli.worker.time.sleep", side_effect=fake_sleep):
            run_worker()
        return state["first_wait"], state["peak"], state["started"]

    def test_worker_runs_three_tasks_of_one_widget_when_limit_is_three(self):
        first_wait, peak, total = self._run_worker_for_one_widget(
            {"GLANCE_WORKER_PER_WIDGET_CONCURRENT": "3"}, expected_parallel=3)
        self.assertEqual(first_wait, 3)  # the fourth task waited for a free slot
        self.assertEqual(peak, 3)
        self.assertEqual(total, 4)

    def test_worker_per_widget_limit_zero_uses_every_slot(self):
        first_wait, peak, total = self._run_worker_for_one_widget(
            {"GLANCE_WORKER_PER_WIDGET_CONCURRENT": "0",
             "GLANCE_WORKER_MAX_CONCURRENT": "5"}, expected_parallel=5)
        self.assertEqual(first_wait, 5)  # only the global limit stopped pulling
        self.assertEqual(peak, 5)
        self.assertEqual(total, 6)

    def test_worker_default_runs_one_task_per_widget(self):
        first_wait, peak, total = self._run_worker_for_one_widget({}, expected_parallel=1)
        self.assertEqual(first_wait, 1)
        self.assertEqual(peak, 1)
        self.assertEqual(total, 2)


class DirectFirstAPITests(unittest.TestCase):
    """The API is reached without the environment proxy first; see api._open."""

    ENVELOPE = b'{"success": true, "result": {"ok": true}}'

    def setUp(self):
        patcher = patch.dict(os.environ, {"GLANCE_API_DIRECT": "1"})
        patcher.start()
        self.addCleanup(patcher.stop)
        proxies = patch("glance_cli.api.getproxies", return_value={"https": "http://127.0.0.1:7890"})
        proxies.start()
        self.addCleanup(proxies.stop)

    def call(self):
        return request("GET", "/api/v2/x", token="t")

    def test_direct_success_never_touches_the_proxy_route(self):
        with patch("glance_cli.api._direct_opener") as direct, \
             patch("glance_cli.api.urlopen") as proxied:
            direct.open.return_value = io.BytesIO(self.ENVELOPE)
            self.assertEqual(self.call(), {"ok": True})
        direct.open.assert_called_once()
        proxied.assert_not_called()

    def test_failed_connection_falls_back_to_the_default_route(self):
        with patch("glance_cli.api._direct_opener") as direct, \
             patch("glance_cli.api.urlopen", return_value=io.BytesIO(self.ENVELOPE)) as proxied:
            direct.open.side_effect = URLError("connect failed")
            self.assertEqual(self.call(), {"ok": True})
        proxied.assert_called_once()

    def test_http_answer_is_not_retried_through_the_proxy(self):
        error = HTTPError("https://x", 401, "Unauthorized", {}, io.BytesIO(b'{"error":{"message":"no"}}'))
        with patch("glance_cli.api._direct_opener") as direct, \
             patch("glance_cli.api.urlopen") as proxied:
            direct.open.side_effect = error
            with self.assertRaises(APIError) as caught:
                self.call()
        self.assertEqual(caught.exception.status, 401)
        proxied.assert_not_called()

    def test_read_timeout_is_not_repeated(self):
        # A pull-batch that timed out may already have claimed a task.
        with patch("glance_cli.api._direct_opener") as direct, \
             patch("glance_cli.api.urlopen") as proxied:
            direct.open.side_effect = TimeoutError("timed out")
            with self.assertRaises(APIError):
                self.call()
        proxied.assert_not_called()

    def test_switch_turns_direct_first_off(self):
        with patch.dict(os.environ, {"GLANCE_API_DIRECT": "0"}), \
             patch("glance_cli.api._direct_opener") as direct, \
             patch("glance_cli.api.urlopen", return_value=io.BytesIO(self.ENVELOPE)):
            self.assertEqual(self.call(), {"ok": True})
        direct.open.assert_not_called()

    def test_without_a_proxy_the_default_route_is_used_directly(self):
        with patch("glance_cli.api.getproxies", return_value={}), \
             patch("glance_cli.api._direct_opener") as direct, \
             patch("glance_cli.api.urlopen", return_value=io.BytesIO(self.ENVELOPE)):
            self.assertEqual(self.call(), {"ok": True})
        direct.open.assert_not_called()



if __name__ == "__main__":
    unittest.main()
