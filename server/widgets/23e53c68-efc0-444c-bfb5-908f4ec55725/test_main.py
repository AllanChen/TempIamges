"""Offline checks for the face-swap Widget (no network, no API key)."""

import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import main as widget


def photo(size, color=(200, 60, 60)):
    return Image.new("RGB", size, color)


def gpt_result(target_png, face_png=None, size=None):
    """What a well-behaved model returns: the target photo, unchanged in framing."""
    image = Image.open(io.BytesIO(target_png)).convert("RGB")
    if size:
        image = image.resize(size)
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return buffer.getvalue()


class WidgetTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.directory = Path(folder.name)
        env = patch.dict(os.environ, {"GLANCE_TASK_OUTPUT_DIR": str(self.directory)})
        env.start()
        self.addCleanup(env.stop)
        for target, name, kwargs in (
            (widget, "get_api_key", {"return_value": "test-key"}),
            (widget.time, "sleep", {}),
            (widget.requests, "post", {"side_effect": AssertionError("unexpected network call")}),
            (widget.requests, "get", {"side_effect": AssertionError("unexpected network call")}),
        ):
            patcher = patch.object(target, name, **kwargs)
            patcher.start()
            self.addCleanup(patcher.stop)

    def run_task(self, target_size, face_size=(512, 512)):
        target = self.directory / "target.png"
        face = self.directory / "face.png"
        photo(target_size).save(target)
        photo(face_size, (60, 60, 200)).save(face)
        task = {"input": {"imagePaths": [str(target), str(face)]}}
        with patch.object(widget, "request_gpt_image",
                          side_effect=lambda target_upload, face_upload, key, size: gpt_result(target_upload.read_bytes())) as call:
            return widget.main(task), call

    def output(self, result):
        return Image.open(result["outputs"][0]["path"]).convert("RGB")

    def test_returns_image_at_target_output_size(self):
        result, _ = self.run_task((600, 900))
        self.assertEqual(self.output(result).size, (683, 1024))

    def test_long_edge_is_clamped_to_2048(self):
        result, _ = self.run_task((4000, 3000))
        self.assertEqual(self.output(result).size, (2048, 1536))

    def test_landscape_is_sent_rotated_and_returned_upright(self):
        result, call = self.run_task((1200, 800))
        sent = Image.open(call.call_args.args[0]).size
        self.assertLess(sent[0], sent[1])
        self.assertEqual(self.output(result).size, (1200, 800))

    def test_face_reference_is_shrunk(self):
        _, call = self.run_task((600, 900), face_size=(3000, 2000))
        face = Image.open(call.call_args.args[1])
        self.assertLessEqual(max(face.size), widget.FACE_MAX_EDGE)

    def test_inputs_are_validated_before_any_call(self):
        valid = self.directory / "valid.png"
        photo((100, 100)).save(valid)
        cases = [
            ({"input": {"imagePaths": [str(valid)]}}, "exactly two"),
            ({"input": {"imagePaths": [str(valid), str(valid), str(valid)]}}, "exactly two"),
            ({"input": {"imagePaths": [str(valid), "/nope.png"]}}, "two existing images"),
            ({"input": {"path": str(valid)}}, "exactly two"),
            ({"input": {}}, "exactly two"),
        ]
        for task, message in cases:
            with self.subTest(message=message):
                with self.assertRaisesRegex(ValueError, message):
                    widget.main(task)

    def test_reframed_result_is_retried_then_fails(self):
        def reframed(target_upload, face_upload, key, size):
            return gpt_result(target_upload.read_bytes(), size=(900, 600))
        target = self.directory / "target.png"
        face = self.directory / "face.png"
        photo((600, 900)).save(target)
        photo((512, 512)).save(face)
        with patch.object(widget, "request_gpt_image", side_effect=reframed) as call:
            with self.assertRaises(widget.ReframedError):
                widget.main({"input": {"imagePaths": [str(target), str(face)]}})
        self.assertEqual(call.call_count, widget.MAX_RETRIES)

    def test_transient_errors_are_retried(self):
        attempts = []
        def flaky(target_upload, face_upload, key, size):
            attempts.append(1)
            if len(attempts) < 2:
                raise RuntimeError("busy")
            return gpt_result(target_upload.read_bytes())
        target = self.directory / "target.png"
        face = self.directory / "face.png"
        photo((600, 900)).save(target)
        photo((512, 512)).save(face)
        with patch.object(widget, "request_gpt_image", side_effect=flaky):
            result = widget.main({"input": {"imagePaths": [str(target), str(face)]}})
        self.assertEqual(len(attempts), 2)
        self.assertEqual(result["outputs"][0]["type"], "image")

    def test_moderation_is_explained_and_not_retried(self):
        target = self.directory / "target.png"
        face = self.directory / "face.png"
        photo((600, 900)).save(target)
        photo((512, 512)).save(face)
        with patch.object(widget, "request_gpt_image",
                          side_effect=widget.ModerationRejectedError("blocked")) as call:
            with self.assertRaisesRegex(ValueError, "content moderation"):
                widget.main({"input": {"imagePaths": [str(target), str(face)]}})
        self.assertEqual(call.call_count, 1)

    def test_missing_key_is_an_error_before_any_call(self):
        target = self.directory / "target.png"
        face = self.directory / "face.png"
        photo((600, 900)).save(target)
        photo((512, 512)).save(face)
        with patch.object(widget, "get_api_key", return_value=""), \
                patch.object(widget, "request_gpt_image",
                             side_effect=AssertionError("must not be called")):
            with self.assertRaisesRegex(ValueError, "GULU_GPTIMAGE_KEY"):
                widget.main({"input": {"imagePaths": [str(target), str(face)]}})

    def test_extreme_aspect_ratio_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "aspect ratio"):
            self.run_task((300, 1500))

    def test_moderation_detection(self):
        self.assertTrue(widget.is_moderation_rejection(400, {"error": {"code": "moderation_blocked"}}))
        self.assertFalse(widget.is_moderation_rejection(500, {"error": {"code": "moderation_blocked"}}))
        self.assertFalse(widget.is_moderation_rejection(404, {"error": {"type": "model_not_found"}}))


if __name__ == "__main__":
    unittest.main()
