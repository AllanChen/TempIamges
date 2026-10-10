"""Offline checks for the Widget's task mapping and retry decisions."""

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


CODE_PATH = Path(__file__).with_name("main.py")
spec = importlib.util.spec_from_file_location("widget_under_test", CODE_PATH)
widget = importlib.util.module_from_spec(spec)
spec.loader.exec_module(widget)


class WidgetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.input_path = self.directory / "input.png"
        self.input_path.write_bytes(b"\x89PNG\r\n\x1a\ninput")
        self.output_path = self.directory / "result.png"
        self.output_path.write_bytes(b"\x89PNG\r\n\x1a\nresult")
        self.task = {"input": {"path": str(self.input_path)}, "parameters": {}}

    def run_with_responses(self, responses):
        with (
            patch.dict(os.environ, {
                "RUNNINGHUB_API_KEY_AI": "test-key",
                "GLANCE_TASK_OUTPUT_DIR": str(self.directory),
            }),
            patch.object(widget, "upload_image", return_value="uploaded.png"),
            patch.object(widget, "post_json", side_effect=responses) as post,
            patch.object(widget, "download_image", return_value=self.output_path),
            patch.object(widget.time, "sleep"),
        ):
            result = widget.main(self.task)
        return result, post

    def test_single_image_is_mapped_to_the_outpainting_app_and_node(self):
        result, post = self.run_with_responses([
            {"taskId": "generation-1"},
            {"status": "SUCCESS", "results": [{"url": "https://example.com/image.png"}]},
        ])
        self.assertEqual(result, {
            "outputs": [{"type": "image", "path": str(self.output_path)}]
        })
        submission = post.call_args_list[0].args[1]
        self.assertEqual(post.call_args_list[0].args[0], widget.RUN_URL)
        self.assertEqual(widget.RUN_URL,
                         "https://www.runninghub.ai/openapi/v2/run/ai-app/2108809728910839809")
        self.assertEqual(submission["nodeInfoList"], [{
            "nodeId": "286",
            "fieldName": "image",
            "fieldValue": "uploaded.png",
            "description": None,
        }])
        self.assertEqual(post.call_args_list[1].args[1], {"taskId": "generation-1"})

    def test_ordinary_generation_failure_submits_a_new_task(self):
        _, post = self.run_with_responses([
            {"taskId": "generation-1"},
            {"status": "FAILED", "errorMessage": "temporary generation error"},
            {"taskId": "generation-2"},
            {"status": "SUCCESS", "results": [{"url": "https://example.com/image.png"}]},
        ])
        submissions = [call for call in post.call_args_list if call.args[3] == "submit"]
        self.assertEqual(len(submissions), 2)

    def test_porn_and_political_rejections_never_resubmit(self):
        for reason in ("Porn", "Political content"):
            with self.subTest(reason=reason):
                with (
                    patch.dict(os.environ, {"RUNNINGHUB_API_KEY_AI": "test-key"}),
                    patch.object(widget, "upload_image", return_value="uploaded.png"),
                    patch.object(widget, "post_json", side_effect=[
                        {"taskId": "generation-1"},
                        {"status": "FAILED", "failedReason": json.dumps({
                            "exception_type": "audit.RHAuditException",
                            "exception_message": reason,
                        })},
                    ]) as post,
                ):
                    with self.assertRaises(widget.AuditRejectedError):
                        widget.main(self.task)
                self.assertEqual(len(post.call_args_list), 2)

    def test_uncertain_submission_is_not_repeated(self):
        with (
            patch.dict(os.environ, {"RUNNINGHUB_API_KEY_AI": "test-key"}),
            patch.object(widget, "upload_image", return_value="uploaded.png"),
            patch.object(widget, "post_json", side_effect=widget.SubmissionStateUnknownError(
                "submit response was lost"
            )) as post,
        ):
            with self.assertRaises(widget.SubmissionStateUnknownError):
                widget.main(self.task)
        self.assertEqual(post.call_count, 1)

    def test_upload_uses_ai_domain_and_returns_filename_for_image_node(self):
        with patch.object(widget, "request_json", return_value={
            "code": 0, "data": {"fileName": "api/uploaded.png"}
        }) as request:
            filename = widget.upload_image(self.input_path, "test-key", float("inf"))
        self.assertEqual(filename, "api/uploaded.png")
        upload = request.call_args.args[0]
        self.assertEqual(upload.full_url, "https://www.runninghub.ai/task/openapi/upload")
        self.assertIn(b'name="apiKey"\r\n\r\ntest-key', upload.data)
        self.assertIn(b'name="fileType"\r\n\r\ninput', upload.data)
        self.assertIn(b'name="file"; filename="input.png"', upload.data)

    def test_cn_key_is_not_used_for_ai_requests(self):
        with patch.dict(os.environ, {"RUNNINGHUB_API_KEY_AI": "", "RUNNINGHUB_API_KEY": "cn-key"}), \
             patch.object(widget, "upload_image") as upload:
            with self.assertRaisesRegex(ValueError, "RUNNINGHUB_API_KEY_AI"):
                widget.main(self.task)
        upload.assert_not_called()


if __name__ == "__main__":
    unittest.main()
