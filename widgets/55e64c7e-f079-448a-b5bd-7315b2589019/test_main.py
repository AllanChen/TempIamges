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
        result = widget.main({"input": {"url": "https://example.com/photo.png"}})
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
                                            "path": str(image)}})
        self.assertEqual(result["outputs"][0]["text"], RESULT["image"]["url"])
        self.assertEqual(open_url.call_count, 1)

    def test_missing_key_and_private_url_are_rejected(self):
        with patch.dict(os.environ, {"FREEIMAGEKEY": ""}):
            with self.assertRaisesRegex(ValueError, "FREEIMAGEKEY"):
                widget.main("https://example.com/photo.png")
        with self.assertRaisesRegex(ValueError, "内网地址"):
            widget.image_url("http://127.0.0.1/photo.png")


if __name__ == "__main__":
    unittest.main()
