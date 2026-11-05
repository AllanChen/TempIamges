"""Offline check that the Widget runs without third-party Python packages."""

import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import main as widget


class WidgetHTTPTest(unittest.TestCase):
    def test_main_uploads_and_returns_image_without_requests(self):
        seen = []
        replies = [
            {"code": 0, "data": {"fileName": "remote/input.png"}},
            {"taskId": "runninghub-task"},
            {"status": "SUCCESS", "results": [{"url": "https://example.com/result.png"}]},
        ]

        def fake_urlopen(request, timeout):
            self.assertEqual(timeout, 60)
            seen.append(request)
            if request.full_url == "https://example.com/result.png":
                return io.BytesIO(b"result image bytes")
            return io.BytesIO(json.dumps(replies.pop(0)).encode("utf-8"))

        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "input.png"
            image.write_bytes(b"image bytes")
            with patch.dict("os.environ", {"RUNNINGHUB_API_KEY": "test-key",
                                        "GLANCE_TASK_OUTPUT_DIR": directory}), \
                    patch.object(widget, "urlopen", side_effect=fake_urlopen):
                result = widget.main({"input": {"path": str(image)}})
            self.assertEqual(result["outputs"][0]["type"], "image")
            self.assertEqual(Path(result["outputs"][0]["path"]).read_bytes(), b"result image bytes")

        self.assertEqual([request.full_url for request in seen],
                         [widget.UPLOAD_URL, widget.RUN_URL, widget.QUERY_URL,
                          "https://example.com/result.png"])
        self.assertIn(b'name="apiKey"\r\n\r\ntest-key', seen[0].data)
        self.assertIn(b'name="fileType"\r\n\r\nimage', seen[0].data)
        self.assertIn(b'filename="input.png"', seen[0].data)
        self.assertIn(b"image bytes", seen[0].data)
        self.assertEqual(seen[1].get_header("Authorization"), "Bearer test-key")
        self.assertEqual(seen[1].full_url,
                         "https://www.runninghub.cn/openapi/v2/run/ai-app/2117102824717897730")
        self.assertEqual(json.loads(seen[1].data), {
            "nodeInfoList": [
                {"nodeId": "6", "fieldName": "text",
                 "fieldValue": "Remove all watermarks from the picture. Keep the characters, backgrounds, etc. unchanged except for the watermarks",
                 "description": "text"},
                {"nodeId": "191", "fieldName": "image",
                 "fieldValue": "remote/input.png", "description": "image"},
            ],
            "instanceType": "default",
            "usePersonalQueue": "false",
        })
        self.assertEqual(json.loads(seen[2].data), {"taskId": "runninghub-task"})
        manifest = json.loads(Path(__file__).with_name("widget.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["commands"][0]["outputs"], ["image"])


if __name__ == "__main__":
    unittest.main()
