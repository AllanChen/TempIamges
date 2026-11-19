"""Offline checks for the RunningHub request and Glance output contract."""

import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import main as widget


class WidgetTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.image = Path(self.folder.name) / "sample.png"
        self.image.write_bytes(b"image bytes")

    def test_image_upload_and_inline_text_result(self):
        responses = iter([
            b'{"code":0,"data":{"fileName":"openapi/input.png"}}',
            b'{"taskId":"task-1","status":"QUEUED"}',
            b'{"status":"SUCCESS","results":[{"text":"A mountain at sunrise"}]}',
        ])
        requests = []

        def fake_open(request, timeout):
            requests.append(request)
            return io.BytesIO(next(responses))

        with patch.dict(os.environ, {"RUNNINGHUB_API_KEY": "test-key"}), patch.object(widget, "urlopen", side_effect=fake_open):
            result = widget.main({"input": {"path": str(self.image)}})

        self.assertEqual(result, {"outputs": [{"type": "text", "text": "A mountain at sunrise"}]})
        self.assertEqual([request.full_url for request in requests], [widget.UPLOAD_URL, widget.RUN_URL, widget.QUERY_URL])
        self.assertIn(b"image bytes", requests[0].data)
        self.assertIn(b'"fieldValue": "openapi/input.png"', requests[1].data)
        self.assertIn(b'"nodeId": "1"', requests[1].data)
        self.assertEqual(requests[1].get_header("Authorization"), "Bearer test-key")

    def test_text_file_result(self):
        requests = []

        def fake_open(request, timeout):
            requests.append(request)
            if request.full_url == "https://example.com/output.txt":
                return io.BytesIO("图中有一只猫".encode("utf-8"))
            return io.BytesIO({
                widget.UPLOAD_URL: b'{"code":200,"data":{"filename":"openapi/input.png"}}',
                widget.RUN_URL: b'{"taskId":"task-2"}',
                widget.QUERY_URL: b'{"status":"SUCCESS","results":[{"url":"https://example.com/output.txt","outputType":"txt"}]}',
            }[request.full_url])

        with patch.dict(os.environ, {"RUNNINGHUB_API_KEY": "test-key"}), patch.object(widget, "urlopen", side_effect=fake_open):
            result = widget.main({"input": {"path": str(self.image)}})

        self.assertEqual(result["outputs"][0]["text"], "图中有一只猫")
        self.assertEqual(requests[-1].full_url, "https://example.com/output.txt")

    def test_missing_api_key_fails_before_upload(self):
        with patch.dict(os.environ, {"RUNNINGHUB_API_KEY": ""}), patch.object(widget, "urlopen") as urlopen:
            with self.assertRaisesRegex(ValueError, "RUNNINGHUB_API_KEY"):
                widget.main({"input": {"path": str(self.image)}})
        urlopen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
