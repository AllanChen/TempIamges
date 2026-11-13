"""Offline checks for the GPT-first image-to-prompt Widget (no network, no API key)."""

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from PIL import Image

import main as widget


def reply(status=200, text="A woman on an escalator", finish="stop", body=None):
    response = MagicMock(status_code=status, text=str(body or text))
    response.json.return_value = body if body is not None else {
        "choices": [{"message": {"content": text}, "finish_reason": finish}]}
    return response


class WidgetTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.image = Path(folder.name) / "sample.png"
        Image.new("RGB", (3000, 2000), (10, 120, 200)).save(self.image)
        self.task = {"input": {"path": str(self.image)}}
        for target, kwargs in (
            (widget, {"name": "get_api_key", "return_value": "test-key"}),
            (widget.time, {"name": "sleep"}),
            (widget.runninghub_fallback, {"name": "run", "side_effect": AssertionError("unexpected RunningHub call")}),
        ):
            patcher = patch.object(target, kwargs.pop("name"), **kwargs)
            patcher.start()
            self.addCleanup(patcher.stop)

    def run_main(self, replies, fallback_result=None):
        with patch.object(widget.requests, "post", side_effect=replies) as post, \
                patch.object(widget.runninghub_fallback, "run",
                             return_value=fallback_result or {"outputs": [{"type": "text", "text": "fallback"}]}) as fallback:
            return widget.main(self.task), post, fallback

    def test_gpt_text_is_returned_without_touching_runninghub(self):
        result, post, fallback = self.run_main([reply()])
        self.assertEqual(result, {"outputs": [{"type": "text", "text": "A woman on an escalator"}]})
        fallback.assert_not_called()
        request = post.call_args
        self.assertEqual(request.args[0], "https://guluapi.com/v1/chat/completions")
        self.assertEqual(request.kwargs["headers"]["Authorization"], "Bearer test-key")
        payload = request.kwargs["json"]
        self.assertEqual(payload["model"], widget.MODEL)
        url = payload["messages"][1]["content"][0]["image_url"]["url"]
        self.assertTrue(url.startswith("data:image/jpeg;base64,"))

    def test_image_is_downscaled_before_upload(self):
        import base64, io
        url = widget.image_data_url(self.image)
        image = Image.open(io.BytesIO(base64.b64decode(url.split(",", 1)[1])))
        self.assertEqual(max(image.size), widget.MAX_IMAGE_EDGE)

    def test_transient_error_is_retried_before_falling_back(self):
        result, post, fallback = self.run_main([reply(status=500), reply(text="second try")])
        self.assertEqual(result["outputs"][0]["text"], "second try")
        self.assertEqual(post.call_count, 2)
        fallback.assert_not_called()

    def test_persistent_failure_falls_back_to_runninghub(self):
        result, post, fallback = self.run_main([reply(status=500)] * widget.MAX_RETRIES)
        self.assertEqual(post.call_count, widget.MAX_RETRIES)
        fallback.assert_called_once_with(self.task)
        self.assertEqual(result["outputs"][0]["text"], "fallback")

    def test_empty_text_or_refusal_falls_back(self):
        for empty in (reply(text="", finish="content_filter"), reply(body={"choices": []})):
            with self.subTest(empty=empty.text):
                _, _, fallback = self.run_main([empty] * widget.MAX_RETRIES)
                fallback.assert_called_once()

    def test_missing_key_falls_back_without_calling_gpt(self):
        with patch.object(widget, "get_api_key", return_value=""):
            _, post, fallback = self.run_main([])
        post.assert_not_called()
        fallback.assert_called_once()

    def test_missing_image_fails_before_any_call(self):
        with patch.object(widget.requests, "post") as post:
            with self.assertRaisesRegex(ValueError, "existing image"):
                widget.main({"input": {"path": "/nope.png"}})
        post.assert_not_called()


if __name__ == "__main__":
    unittest.main()
