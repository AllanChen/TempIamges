"""Offline checks for the two-image GPT Image outfit Widget (no network, no API key)."""

import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import main as widget


def write_image(path: Path, size, color=(120, 90, 60)):
    Image.new("RGB", size, color).save(path, "PNG")
    return path


def png_bytes(size):
    buffer = io.BytesIO()
    Image.new("RGB", size, (10, 20, 30)).save(buffer, "PNG")
    return buffer.getvalue()


class WidgetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        env = patch.dict(os.environ, {"GLANCE_TASK_OUTPUT_DIR": str(self.directory)})
        env.start()
        self.addCleanup(env.stop)
        key = patch.object(widget, "get_api_key", return_value="test-key")
        key.start()
        self.addCleanup(key.stop)
        # Never reach the real RunningHub from tests, even when RUNNINGHUB_API_KEY is set.
        guard = patch.object(widget.runninghub_fallback, "run",
                             side_effect=AssertionError("unexpected real RunningHub call"))
        guard.start()
        self.addCleanup(guard.stop)
        blocked = patch.object(widget.requests, "post", side_effect=AssertionError("unexpected network call"))
        blocked.start()
        self.addCleanup(blocked.stop)
        sleep = patch.object(widget.time, "sleep")
        sleep.start()
        self.addCleanup(sleep.stop)

    def run_task(self, person_size, replies):
        person = write_image(self.directory / "person.png", person_size)
        outfit = write_image(self.directory / "outfit.png", (600, 800), (30, 60, 200))
        with patch.object(widget, "request_gpt_image", side_effect=replies) as call:
            result = widget.main({"input": {"imagePaths": [str(person), str(outfit)]}})
        return result, call

    def run_task_with_fallback(self, person_size, replies, fallback_error=None):
        person = write_image(self.directory / "person.png", person_size)
        outfit = write_image(self.directory / "outfit.png", (600, 800), (30, 60, 200))
        fallback_result = {"outputs": [{"type": "image", "path": "fallback.png"}]}
        with patch.object(widget, "request_gpt_image", side_effect=replies) as call, \
                patch.object(widget.runninghub_fallback, "run", side_effect=fallback_error,
                             return_value=fallback_result) as fallback:
            result = widget.main({"input": {"imagePaths": [str(person), str(outfit)]}})
        return result, call, fallback

    def result_size(self, result):
        return Image.open(result["outputs"][0]["path"]).size

    def test_portrait_result_keeps_the_person_photo_size(self):
        result, call = self.run_task((941, 1672), [png_bytes((942, 1670))])
        self.assertEqual(self.result_size(result), (941, 1672))
        person_upload, outfit_upload, key, size = call.call_args.args
        self.assertEqual(Image.open(person_upload).size, (941, 1672))
        self.assertEqual(key, "test-key")

    def test_landscape_is_sent_rotated_and_returned_upright(self):
        result, call = self.run_task((1448, 1086), [png_bytes((1086, 1448))])
        self.assertEqual(self.result_size(result), (1448, 1086))
        self.assertEqual(Image.open(call.call_args.args[0]).size, (1086, 1448))

    def test_size_is_clamped_to_1024_2048_long_edge(self):
        result, _ = self.run_task((4344, 3258), [png_bytes((1536, 2048))])
        self.assertEqual(self.result_size(result), (2048, 1536))
        result, _ = self.run_task((600, 800), [png_bytes((768, 1024))])
        self.assertEqual(self.result_size(result), (768, 1024))

    def test_reframed_result_is_retried_then_falls_back_to_runninghub(self):
        result, call, fallback = self.run_task_with_fallback((941, 1672), [png_bytes((1672, 941))] * 2)
        self.assertEqual(call.call_count, widget.MAX_RETRIES)
        fallback.assert_called_once()
        self.assertEqual(result, {"outputs": [{"type": "image", "path": "fallback.png"}]})

    def test_moderation_rejection_falls_back_to_runninghub_without_retrying(self):
        result, call, fallback = self.run_task_with_fallback(
            (941, 1672), widget.ModerationRejectedError("blocked"))
        self.assertEqual(call.call_count, 1)
        fallback.assert_called_once()
        self.assertEqual(result["outputs"][0]["path"], "fallback.png")

    def test_runninghub_failure_after_gpt_failure_fails_the_task(self):
        with self.assertRaisesRegex(RuntimeError, "RunningHub down"):
            self.run_task_with_fallback((941, 1672), widget.ModerationRejectedError("x"),
                                        fallback_error=RuntimeError("RunningHub down"))

    def test_gpt_success_does_not_touch_runninghub(self):
        _, _, fallback = self.run_task_with_fallback((941, 1672), [png_bytes((941, 1672))])
        fallback.assert_not_called()

    def test_transient_errors_are_retried(self):
        result, call, fallback = self.run_task_with_fallback(
            (941, 1672), [RuntimeError("busy"), png_bytes((941, 1672))])
        self.assertEqual(call.call_count, 2)
        fallback.assert_not_called()
        self.assertEqual(Image.open(result["outputs"][0]["path"]).size, (941, 1672))

    def test_moderation_detection(self):
        self.assertTrue(widget.is_moderation_rejection(400, {"error": {"code": "moderation_blocked"}}))
        self.assertTrue(widget.is_moderation_rejection(400, {"error": {"message": "rejected by the safety system"}}))
        self.assertFalse(widget.is_moderation_rejection(500, {"error": {"code": "moderation_blocked"}}))
        self.assertFalse(widget.is_moderation_rejection(404, {"error": {"type": "model_not_found"}}))

    def test_requires_exactly_two_images_before_any_call(self):
        with patch.object(widget, "request_gpt_image") as call:
            with self.assertRaisesRegex(ValueError, "exactly two"):
                widget.main({"input": {"imagePaths": ["one.png"]}})
        call.assert_not_called()

    def test_extreme_aspect_ratio_skips_gpt_and_uses_runninghub(self):
        result, call, fallback = self.run_task_with_fallback((300, 1500), [])
        call.assert_not_called()
        fallback.assert_called_once()
        self.assertEqual(result["outputs"][0]["path"], "fallback.png")


if __name__ == "__main__":
    unittest.main()
