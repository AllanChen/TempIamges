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

from glance_cli.cli import main
from glance_cli.api import APIError
from glance_cli.registry import connect, eligible, read_session, rows, update
from glance_cli.runtime import execute, validate_outputs
from glance_cli.worker import _run_task
from glance_cli.worker_logs import configure_worker_logging, logger


class CLITest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        patcher = patch.dict(os.environ, {"GLANCE_CLI_HOME": str(self.root / "config")})
        patcher.start()
        self.addCleanup(patcher.stop)

    def create_widget(self):
        self.assertEqual(main(["widget", "init", "--directory", str(self.root)]), 0)
        widget = next(path for path in self.root.iterdir() if path.name != "config")
        return widget, json.loads((widget / "widget.json").read_text())

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

    def test_image_return_url_is_uploaded_as_text_asset(self):
        widget = self.root / "widget"
        widget.mkdir()
        image = widget / "result.png"
        image.write_bytes(b"\x89PNG\r\n\x1a\n")
        outputs = validate_outputs({"outputs": [{"type": "image", "path": str(image),
                                                   "returnURL": True}]}, widget)
        self.assertTrue(outputs[0]["returnURL"])

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
                         [{"type": "text", "assetID": "asset_1"}])

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
        with patch("glance_cli.cli.read_session", return_value={"token": "test"}), \
             patch("glance_cli.cli.request", return_value=detail):
            self.assertEqual(main(["widget", "add", str(folder)]), 0)
        with closing(connect()) as db:
            self.assertEqual(rows(db)[0]["server_status"], "published")
            self.assertEqual(rows(db)[0]["enabled"], 1)
        with patch("glance_cli.cli.read_session", return_value={"token": "test"}), \
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
