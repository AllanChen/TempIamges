"""Offline checks for the masked-edit Widget (no network, no API key)."""

import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image, ImageDraw

import main as widget


def photo_image(size):
    return Image.new("RGB", size, (200, 60, 60))


def client_mask(size, box):
    """What Glance's mask editor exports: opaque white strokes on a transparent PNG."""
    mask = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(mask).rectangle(box, fill=(255, 255, 255, 255))
    return mask


def gpt_result(photo_png, mask_png=None, size=None, color=(30, 90, 200)):
    """What a well-behaved model returns: the photo with only the white mask area repainted."""
    image = Image.open(io.BytesIO(photo_png)).convert("RGB")
    if mask_png is not None:
        image.paste(Image.new("RGB", image.size, color), (0, 0), Image.open(io.BytesIO(mask_png)).convert("L"))
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

    def run_task(self, size, box, replies, prompt="remove it", mask=None):
        source = self.directory / "input.png"
        photo_image(size).save(source)
        mask = mask or client_mask(size, box)
        task = {"input": {"path": str(source)}, "parameters": {"prompt": prompt, "mask": "https://example.com/mask.png"}}
        with patch.object(widget, "fetch_mask", return_value=mask), \
                patch.object(widget, "request_gpt_image", side_effect=replies) as call:
            return widget.main(task), call

    def echo(self, **options):
        return lambda photo_png, mask_png, prompt, key, size: gpt_result(photo_png, mask_png, **options)

    def output(self, result):
        return Image.open(result["outputs"][0]["path"]).convert("RGB")

    def test_only_the_masked_area_changes(self):
        result, call = self.run_task((600, 900), (200, 300, 400, 600), self.echo())
        output = self.output(result)
        self.assertEqual(output.size, (683, 1024))
        scale = output.size[0] / 600
        self.assertEqual(output.getpixel((round(300 * scale), round(450 * scale))), (30, 90, 200))   # inside: GPT
        self.assertEqual(output.getpixel((round(30 * scale), round(30 * scale))), (200, 60, 60))      # outside: original

    def test_request_carries_photo_mask_prompt_and_key(self):
        _, call = self.run_task((600, 900), (200, 300, 400, 600), self.echo(), prompt="换成一盆绿植")
        photo_png, mask_png, prompt, key, size = call.call_args.args
        self.assertEqual(Image.open(io.BytesIO(photo_png)).size, Image.open(io.BytesIO(mask_png)).size)
        mask = Image.open(io.BytesIO(mask_png)).convert("L")
        self.assertEqual(mask.getpixel((mask.width // 2, mask.height // 2)), 255)
        self.assertEqual(mask.getpixel((5, 5)), 0)
        self.assertEqual((prompt, key), ("换成一盆绿植", "test-key"))

    def test_landscape_is_sent_rotated_and_returned_upright(self):
        result, call = self.run_task((1200, 800), (400, 300, 800, 500), self.echo())
        sent = Image.open(io.BytesIO(call.call_args.args[0])).size
        self.assertLess(sent[0], sent[1])
        self.assertEqual(self.output(result).size, (1200, 800))

    def test_long_edge_is_clamped_to_2048_and_small_images_grow_to_1024(self):
        result, _ = self.run_task((4000, 3000), (1000, 1000, 2000, 2000), self.echo())
        self.assertEqual(self.output(result).size, (2048, 1536))
        result, _ = self.run_task((600, 800), (100, 100, 300, 300), self.echo())
        self.assertEqual(max(self.output(result).size), 1024)

    def test_black_and_white_masks_are_understood_and_stretched(self):
        mask = Image.new("RGB", (60, 90), (0, 0, 0))
        ImageDraw.Draw(mask).rectangle((20, 30, 40, 60), fill=(255, 255, 255))
        result, call = self.run_task((600, 900), None, self.echo(), mask=mask)
        sent = Image.open(io.BytesIO(call.call_args.args[1])).convert("L")
        self.assertEqual(sent.getpixel((sent.width // 2, sent.height // 2)), 255)
        self.assertEqual(sent.getpixel((3, 3)), 0)

    def test_black_painted_area_is_not_selected(self):
        mask = Image.new("RGBA", (600, 900), (0, 0, 0, 255))      # opaque black everywhere
        with self.assertRaisesRegex(ValueError, "mask is empty"):
            self.run_task((600, 900), None, [], mask=mask)

    def test_empty_mask_fails_before_any_call(self):
        with self.assertRaisesRegex(ValueError, "mask is empty"):
            _, call = self.run_task((600, 900), (0, 0, 0, 0), self.echo(), mask=Image.new("RGBA", (600, 900), (0, 0, 0, 0)))

    def test_reframed_result_is_retried_then_fails(self):
        with patch.object(widget, "fetch_mask", return_value=client_mask((600, 900), (200, 300, 400, 600))), \
                patch.object(widget, "request_gpt_image",
                             side_effect=lambda p, m, pr, k, s: gpt_result(p, m, size=(900, 600))) as call:
            source = self.directory / "input.png"
            photo_image((600, 900)).save(source)
            with self.assertRaises(widget.BadResultError):
                widget.main({"input": {"path": str(source)}, "parameters": {"prompt": "x", "mask": "https://e.com/m.png"}})
        self.assertEqual(call.call_count, widget.MAX_RETRIES)

    def test_redrawn_photo_outside_the_mask_is_rejected(self):
        def shifted(photo_png, mask_png, prompt, key, size):
            image = Image.new("RGB", Image.open(io.BytesIO(photo_png)).size, (20, 250, 250))
            buffer = io.BytesIO()
            image.save(buffer, "PNG")
            return buffer.getvalue()
        with self.assertRaises(widget.BadResultError):
            self.run_task((600, 900), (200, 300, 400, 600), shifted)

    def test_moderation_is_explained_and_not_retried(self):
        with self.assertRaisesRegex(ValueError, "content moderation"):
            self.run_task((600, 900), (200, 300, 400, 600), widget.ModerationRejectedError("blocked"))
        with patch.object(widget, "fetch_mask", return_value=client_mask((600, 900), (200, 300, 400, 600))), \
                patch.object(widget, "request_gpt_image", side_effect=widget.ModerationRejectedError("x")) as call:
            source = self.directory / "input.png"
            with self.assertRaises(ValueError):
                widget.main({"input": {"path": str(source)}, "parameters": {"prompt": "x", "mask": "https://e.com/m.png"}})
        self.assertEqual(call.call_count, 1)

    def test_transient_errors_are_retried(self):
        replies = [RuntimeError("busy"), lambda *a: gpt_result(a[0], a[1])]
        calls = []
        def flaky(*args):
            calls.append(1)
            reply = replies[len(calls) - 1]
            if isinstance(reply, Exception):
                raise reply
            return reply(*args)
        result, call = self.run_task((600, 900), (200, 300, 400, 600), flaky)
        self.assertEqual(len(calls), 2)

    def test_inputs_are_validated_before_any_call(self):
        source = self.directory / "input.png"
        photo_image((600, 900)).save(source)
        cases = [
            ({"input": {"path": str(source)}, "parameters": {"prompt": 5, "mask": "https://e.com/m.png"}}, "must be text"),
            ({"input": {"path": str(source)}, "parameters": {"prompt": "x"}}, "mask is required"),
            ({"input": {"path": str(source)}, "parameters": {"prompt": "x", "mask": "http://e.com/m.png"}}, "https"),
            ({"input": {"path": str(source)}, "parameters": {"prompt": "x" * 2001, "mask": "https://e.com/m.png"}}, "too long"),
            ({"input": {"path": "/nope.png"}, "parameters": {"prompt": "x", "mask": "https://e.com/m.png"}}, "existing image"),
        ]
        for task, message in cases:
            with self.subTest(message=message):
                with self.assertRaisesRegex(ValueError, message):
                    widget.main(task)

    def test_missing_or_blank_prompt_removes_the_object(self):
        for parameters in ({}, {"prompt": ""}, {"prompt": "   "}, {"prompt": None}):
            with self.subTest(parameters=parameters):
                source = self.directory / "input.png"
                photo_image((600, 900)).save(source)
                with patch.object(widget, "fetch_mask", return_value=client_mask((600, 900), (200, 300, 400, 600))), \
                        patch.object(widget, "request_gpt_image", side_effect=self.echo()) as call:
                    widget.main({"input": {"path": str(source)},
                                 "parameters": {**parameters, "mask": "https://e.com/m.png"}})
                self.assertEqual(call.call_args.args[2], widget.DEFAULT_PROMPT)
                self.assertIn("Remove the object", widget.DEFAULT_PROMPT)

    def test_extreme_aspect_ratio_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "aspect ratio"):
            self.run_task((300, 1500), (10, 10, 100, 100), [])

    def test_moderation_detection(self):
        self.assertTrue(widget.is_moderation_rejection(400, {"error": {"code": "moderation_blocked"}}))
        self.assertFalse(widget.is_moderation_rejection(500, {"error": {"code": "moderation_blocked"}}))
        self.assertFalse(widget.is_moderation_rejection(404, {"error": {"type": "model_not_found"}}))


if __name__ == "__main__":
    unittest.main()
