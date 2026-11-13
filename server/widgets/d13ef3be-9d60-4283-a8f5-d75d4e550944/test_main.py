"""Offline checks for the GPT-first Expand Image Widget (no network, no API key)."""

import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import main as widget


def photo_image(size):
    image = Image.new("RGB", size, (200, 60, 60))
    image.paste((30, 90, 200), (size[0] // 4, size[1] // 4, size[0] * 3 // 4, size[1] * 3 // 4))
    return image


def gpt_result(canvas_path, fill=(40, 160, 70), size=None, border_alpha=255):
    """What a well-behaved model returns: the canvas with its transparent border filled in."""
    canvas = Image.open(canvas_path).convert("RGBA")
    filled = Image.new("RGBA", canvas.size, fill + (border_alpha,))
    filled.alpha_composite(canvas)
    if size:
        filled = filled.resize(size)
    buffer = io.BytesIO()
    filled.save(buffer, "PNG")
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
            (widget.runninghub_fallback, "run", {"side_effect": AssertionError("unexpected RunningHub call")}),
            (widget.requests, "post", {"side_effect": AssertionError("unexpected network call")}),
        ):
            patcher = patch.object(target, name, **kwargs)
            patcher.start()
            self.addCleanup(patcher.stop)

    def run_task(self, size, side_effect, fallback_error=None):
        source = self.directory / "input.png"
        photo_image(size).save(source)
        fallback_result = {"outputs": [{"type": "image", "path": "fallback.png"}]}
        with patch.object(widget, "request_gpt_image", side_effect=side_effect) as call, \
                patch.object(widget.runninghub_fallback, "run", side_effect=fallback_error,
                             return_value=fallback_result) as fallback:
            result = widget.main({"input": {"path": str(source)}})
        return result, call, fallback

    def echo(self, **options):
        return lambda canvas_path, key, size: gpt_result(canvas_path, **options)

    def test_portrait_is_expanded_by_half_and_keeps_the_original_pixels(self):
        result, call, fallback = self.run_task((600, 900), self.echo())
        fallback.assert_not_called()
        output = Image.open(result["outputs"][0]["path"]).convert("RGB")
        self.assertEqual(output.size, (900, 1350))
        self.assertEqual(output.getpixel((450, 675)), (30, 90, 200))      # original center kept
        self.assertEqual(output.getpixel((10, 10)), (40, 160, 70))         # border generated
        self.assertEqual(call.call_args.args[1], "test-key")

    def test_landscape_canvas_is_sent_rotated_and_returned_upright(self):
        result, call, _ = self.run_task((1200, 800), self.echo())
        sent = Image.open(call.call_args.args[0]).size
        self.assertLess(sent[0], sent[1])
        self.assertEqual(Image.open(result["outputs"][0]["path"]).size, (1800, 1200))

    def test_canvas_long_edge_is_clamped_to_2048(self):
        result, _, _ = self.run_task((2400, 1800), self.echo())
        self.assertEqual(max(Image.open(result["outputs"][0]["path"]).size), 2048)

    def test_reframed_result_is_retried_then_falls_back(self):
        result, call, fallback = self.run_task((600, 900), lambda p, k, s: gpt_result(p, size=(900, 600)))
        self.assertEqual(call.call_count, widget.MAX_RETRIES)
        fallback.assert_called_once()
        self.assertEqual(result["outputs"][0]["path"], "fallback.png")

    def test_untouched_transparent_border_falls_back(self):
        _, call, fallback = self.run_task((600, 900), self.echo(border_alpha=0))
        fallback.assert_called_once()

    def test_moved_or_redrawn_photo_falls_back(self):
        def shifted(canvas_path, key, size):
            image = Image.new("RGB", Image.open(canvas_path).size, (250, 250, 20))
            buffer = io.BytesIO()
            image.save(buffer, "PNG")
            return buffer.getvalue()
        _, _, fallback = self.run_task((600, 900), shifted)
        fallback.assert_called_once()

    def test_moderation_falls_back_without_retrying(self):
        _, call, fallback = self.run_task((600, 900), widget.ModerationRejectedError("blocked"))
        self.assertEqual(call.call_count, 1)
        fallback.assert_called_once()

    def test_transient_error_is_retried_before_falling_back(self):
        def flaky(canvas_path, key, size, calls=[]):
            calls.append(1)
            if len(calls) == 1:
                raise RuntimeError("busy")
            return gpt_result(canvas_path)
        result, call, fallback = self.run_task((600, 900), flaky)
        fallback.assert_not_called()
        self.assertEqual(call.call_count, 2)

    def test_extreme_aspect_and_missing_key_use_runninghub_without_calling_gpt(self):
        _, call, fallback = self.run_task((300, 1500), [])
        call.assert_not_called()
        fallback.assert_called_once()
        with patch.object(widget, "get_api_key", return_value=""):
            _, call, fallback = self.run_task((600, 900), [])
        call.assert_not_called()
        fallback.assert_called_once()

    def test_runninghub_failure_after_gpt_failure_fails_the_task(self):
        with self.assertRaisesRegex(RuntimeError, "RunningHub down"):
            self.run_task((600, 900), widget.ModerationRejectedError("x"),
                          fallback_error=RuntimeError("RunningHub down"))

    def test_moderation_detection(self):
        self.assertTrue(widget.is_moderation_rejection(400, {"error": {"code": "moderation_blocked"}}))
        self.assertFalse(widget.is_moderation_rejection(500, {"error": {"code": "moderation_blocked"}}))
        self.assertFalse(widget.is_moderation_rejection(404, {"error": {"type": "model_not_found"}}))

    def test_missing_image_fails_before_any_call(self):
        with self.assertRaisesRegex(ValueError, "existing image"):
            widget.main({"input": {"path": "/nope.png"}})


if __name__ == "__main__":
    unittest.main()
