"""Offline checks for the two-image RunningHub Widget contract."""

import io
import json
import os
import tempfile
import unittest
from email.message import Message
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError

import main as widget


class ImageResponse(io.BytesIO):
    def __init__(self, content: bytes):
        super().__init__(content)
        self.headers = Message()
        self.headers.add_header("Content-Type", "image/png")


class WidgetTests(unittest.TestCase):
    def test_two_inputs_map_to_nodes_and_return_an_image(self):
        seen = []
        replies = iter([
            {"code": 0, "data": {"fileName": "remote/first.png"}},
            {"code": 0, "data": {"fileName": "remote/second.jpg"}},
            {"taskId": "runninghub-task"},
            {"status": "SUCCESS", "results": [
                {"url": "https://example.com/result.png"},
                {"url": "https://example.com/unused.png"},
            ]},
        ])

        def fake_open(request, timeout):
            self.assertEqual(timeout, 60)
            seen.append(request)
            if request.full_url == "https://example.com/result.png":
                return ImageResponse(b"result image bytes")
            return io.BytesIO(json.dumps(next(replies)).encode("utf-8"))

        with tempfile.TemporaryDirectory() as directory:
            # Glance R2 asset URLs have no filename extension.
            first = Path(directory) / "asset-1"
            second = Path(directory) / "asset-2"
            first.write_bytes(b"\x89PNG\r\n\x1a\nfirst image bytes")
            second.write_bytes(b"\xff\xd8\xffsecond image bytes")
            with patch.dict(os.environ, {"RUNNINGHUB_API_KEY": "test-key",
                                        "GLANCE_TASK_OUTPUT_DIR": directory}), \
                    patch.object(widget, "urlopen", side_effect=fake_open):
                result = widget.main({"input": {"imagePaths": [str(first), str(second)]}})
            self.assertEqual(len(result["outputs"]), 1)
            self.assertEqual(result["outputs"][0]["type"], "image")
            self.assertEqual(Path(result["outputs"][0]["path"]).read_bytes(), b"result image bytes")

        self.assertEqual([request.full_url for request in seen],
                         [widget.UPLOAD_URL, widget.UPLOAD_URL, widget.RUN_URL,
                          widget.QUERY_URL, "https://example.com/result.png"])
        self.assertEqual(widget.RUN_URL,
                         "https://www.runninghub.cn/openapi/v2/run/ai-app/2108493566690545665")
        self.assertIn(b"first image bytes", seen[0].data)
        self.assertIn(b"second image bytes", seen[1].data)
        self.assertIn(b'filename="input.png"', seen[0].data)
        self.assertIn(b'filename="input.jpg"', seen[1].data)
        nodes = json.loads(seen[2].data)["nodeInfoList"]
        self.assertEqual([(node["nodeId"], node["fieldValue"]) for node in nodes],
                         [("207", "remote/first.png"), ("208", "remote/second.jpg")])
        self.assertEqual(seen[2].get_header("Authorization"), "Bearer test-key")

    def test_query_retries_server_errors_without_submitting_again(self):
        calls = []
        responses = iter([
            HTTPError(widget.QUERY_URL, 503, "busy", {}, io.BytesIO(b"temporary")),
            {"status": "SUCCESS", "results": [{"url": "https://example.com/result.png"}]},
        ])

        def fake_open(request, timeout):
            calls.append(request.full_url)
            reply = next(responses)
            if isinstance(reply, Exception):
                raise reply
            return io.BytesIO(json.dumps(reply).encode("utf-8"))

        with patch.object(widget, "urlopen", side_effect=fake_open), \
                patch.object(widget.time, "sleep") as sleep:
            url = widget.wait_for_result("test-key", "task-1")
        self.assertEqual(url, "https://example.com/result.png")
        self.assertEqual(calls, [widget.QUERY_URL, widget.QUERY_URL])
        sleep.assert_called_once_with(2)

    def test_requires_exactly_two_images_before_network_calls(self):
        with patch.object(widget, "urlopen") as urlopen:
            with self.assertRaisesRegex(ValueError, "exactly two"):
                widget.main({"input": {"imagePaths": ["one.png"]}})
        urlopen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
