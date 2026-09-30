import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import main as widget


PNG = b"\x89PNG\r\n\x1a\n" + b"sample-image-data"
RESULT = {"status_code": 200, "image": {"url": "https://iili.io/example.png"}}


class WidgetTest(unittest.TestCase):
    @patch.dict(os.environ, {"FREEIMAGEKEY": "test-key"})
    @patch("main.urlopen")
    def test_url_is_downloaded_and_uploaded_as_multipart(self, open_url):
        open_url.side_effect = [io.BytesIO(PNG), io.BytesIO(json.dumps(RESULT).encode())]
        result = widget.main({"input": {"url": "https://example.com/photo.png"},
                              "parameters": {"location": "China"}})
        self.assertEqual(result, {"outputs": [{"type": "text", "text": RESULT["image"]["url"]}]})
        download, upload = [call.args[0] for call in open_url.call_args_list]
        self.assertEqual(download.full_url, "https://example.com/photo.png")
        self.assertEqual(upload.full_url, widget.UPLOAD_URL)
        self.assertEqual(upload.get_method(), "POST")
        self.assertIn(b'name="key"\r\n\r\ntest-key', upload.data)
        self.assertIn(b'name="action"\r\n\r\nupload', upload.data)
        self.assertIn(b'name="format"\r\n\r\njson', upload.data)
        self.assertIn(b'name="source"; filename="widget-input.png"', upload.data)
        self.assertIn(PNG, upload.data)

    @patch.dict(os.environ, {"FREEIMAGEKEY": "test-key"})
    @patch("main.urlopen")
    def test_cli_predownloaded_file_is_reused(self, open_url):
        open_url.return_value = io.BytesIO(json.dumps(RESULT).encode())
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "image.png"
            image.write_bytes(PNG)
            result = widget.main({"input": {"url": "https://example.com/photo.png",
                                            "path": str(image)},
                                  "parameters": {"location": "CN"}})
        self.assertEqual(result["outputs"][0]["text"], RESULT["image"]["url"])
        self.assertEqual(open_url.call_count, 1)

    @patch("main.urlopen")
    def test_matching_provider_url_is_returned_without_upload(self, open_url):
        for location, url in [
            ("china", "https://iili.io/example.png"),
            ("US", "https://pub-example.r2.dev/example.png"),
            ("US", "https://glance-service.allanchanni.workers.dev/api/v2/assets/asset_1?sig=x"),
        ]:
            with self.subTest(location=location, url=url):
                result = widget.main({"task_params": {"url": url, "location": location}})
                self.assertEqual(result["outputs"], [{"type": "text", "text": url}])
        open_url.assert_not_called()

    @patch.dict(os.environ, {"FREEIMAGEKEY": "test-key"})
    @patch("main.urlopen")
    def test_china_reuploads_r2_url_to_freeimage(self, open_url):
        source = "https://pub-example.r2.dev/example.png"
        open_url.side_effect = [io.BytesIO(PNG), io.BytesIO(json.dumps(RESULT).encode())]
        result = widget.main({"task_params": {"url": source, "location": "China"}})
        self.assertEqual(result["outputs"][0]["text"], RESULT["image"]["url"])
        self.assertEqual(open_url.call_args_list[0].args[0].full_url, source)
        self.assertEqual(open_url.call_args_list[1].args[0].full_url, widget.UPLOAD_URL)

    @patch("main.urlopen")
    def test_other_region_reuploads_freeimage_url_to_r2(self, open_url):
        source = "https://iili.io/example.png"
        open_url.return_value = io.BytesIO(PNG)
        with tempfile.TemporaryDirectory() as directory, patch.dict(
                os.environ, {"GLANCE_TASK_OUTPUT_DIR": directory}):
            result = widget.main({"task_params": {"url": source, "location": "US"}})
            output = result["outputs"][0]
            self.assertEqual(output["type"], "image")
            self.assertTrue(output["returnURL"])
            self.assertEqual(Path(output["path"]).read_bytes(), PNG)
        self.assertEqual(open_url.call_args_list[0].args[0].full_url, source)

    @patch.dict(os.environ, {"FREEIMAGEKEY": "test-key"})
    @patch("main.upload_image", side_effect=RuntimeError("Freeimage failed"))
    @patch("main.urlopen")
    def test_freeimage_failure_falls_back_to_r2(self, open_url, upload):
        open_url.return_value = io.BytesIO(PNG)
        with tempfile.TemporaryDirectory() as directory, patch.dict(
                os.environ, {"GLANCE_TASK_OUTPUT_DIR": directory}):
            result = widget.main({"task_params": {"url": "https://example.com/image.png",
                                                   "location": "China"}})
            self.assertTrue(result["outputs"][0]["returnURL"])
        upload.assert_called_once()

    def test_private_url_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "内网地址"):
            widget.image_url("http://127.0.0.1/photo.png")


if __name__ == "__main__":
    unittest.main()
