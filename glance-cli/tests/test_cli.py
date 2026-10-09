import json
from contextlib import closing, contextmanager, redirect_stdout
import io
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import venv

from glance_cli.cli import main, validate
from glance_cli.api import APIError, request, upload_task_file
from glance_cli.registry import connect, eligible, read_session, read_token, rows, update, upsert
from glance_cli.runtime import execute, prepare_input, validate_outputs
from glance_cli.worker import _run_task, _sync_widget_status
from glance_cli.worker_logs import configure_worker_logging, logger


class CLITest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        patcher = patch.dict(os.environ, {"GLANCE_CLI_HOME": str(self.root / "config"),
                                          "GLANCE_MOCK_TOKEN": ""})
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
            self.assertEqual(eligible(db, set()), [])
            update(db, manifest["id"], manifest["version"],
                   server_status="manual_review", enabled=1)
            self.assertEqual(len(eligible(db, set())), 1)
            self.assertEqual(eligible(db, {(manifest["id"], manifest["version"])}), [])

    def test_result_url_preference_requires_image_output(self):
        _, manifest = self.create_widget()
        command = manifest["commands"][0]
        command["outputs"] = ["image"]
        command["showResultURL"] = True
        validate(manifest)
        command["outputs"] = ["text"]
        with self.assertRaisesRegex(ValueError, "只有图片输出"):
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
            self.assertEqual(eligible(db, set()), [])
            self.assertEqual({row["server_status"] for row in rows(db)}, {"removed"})
            self.assertTrue(all(row["enabled"] == 0 for row in rows(db)))

    def test_worker_stops_polling_version_missing_from_server(self):
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
                             [(manifest["version"], "removed", 0), ("0.2.0", "published", 1)])
            self.assertEqual(len(eligible(db, set())), 1)

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

    def test_add_syncs_authorized_version_and_disables_denied_version(self):
        folder, manifest = self.create_widget()
        detail = {"status": "published", "versions": [
            {"version": manifest["version"], "status": "published"}]}
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


if __name__ == "__main__":
    unittest.main()
