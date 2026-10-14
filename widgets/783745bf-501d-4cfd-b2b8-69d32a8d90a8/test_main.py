"""Local contract checks; never call a paid RunningHub endpoint."""

import importlib.util
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("video_watermark_widget", Path(__file__).with_name("main.py"))
assert SPEC and SPEC.loader
widget = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(widget)


class ProviderContractTests(unittest.TestCase):
    def test_video_node_uses_uploaded_file_name(self):
        with patch.object(widget, "post_json", return_value={"taskId": "remote-123"}) as post:
            self.assertEqual(widget.submit_task("secret", "api/uploaded.mp4", time.monotonic() + 60),
                             "remote-123")
        args, kwargs = post.call_args
        self.assertEqual(args[0], widget.RUN_URL)
        self.assertIn("/openapi/v2/run/workflow/", widget.RUN_URL)
        self.assertTrue(args[1]["addMetadata"])
        self.assertEqual(args[1]["nodeInfoList"], [
            {"nodeId": "184", "fieldName": "video", "fieldValue": "api/uploaded.mp4",
             "description": "video"}
        ])
        self.assertFalse(kwargs["retry_transient"])

    def test_confirmed_failure_retries_but_audit_rejection_does_not(self):
        with tempfile.TemporaryDirectory() as directory:
            clip = Path(directory) / "clip.mp4"
            clip.write_bytes(b"video")
            deadline = time.monotonic() + 60
            with patch.object(widget, "upload_video", return_value="uploaded.mp4"), \
                 patch.object(widget, "submit_task", side_effect=[
                     widget.GenerationFailedError("temporary"), "remote-2"
                 ]) as submit, \
                 patch.object(widget, "wait_for_result", return_value="https://example.com/result.mp4"), \
                 patch.object(widget, "download_video", side_effect=lambda _url, path, *_: path), \
                 patch.object(widget.time, "sleep"):
                self.assertEqual(widget.process_clip(0, clip, Path(directory), "secret", deadline)[0], 0)
                self.assertEqual(submit.call_count, 2)

            with patch.object(widget, "upload_video", return_value="uploaded.mp4"), \
                 patch.object(widget, "submit_task", side_effect=widget.AuditRejectedError("porn")) as submit:
                with self.assertRaises(widget.AuditRejectedError):
                    widget.process_clip(0, clip, Path(directory), "secret", deadline)
                self.assertEqual(submit.call_count, 1)

    def test_failed_clip_becomes_black_instead_of_failing_the_task(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            clip = folder / "clip.mp4"
            clip.write_bytes(b"video")
            deadline = time.monotonic() + 60
            black = folder / "result-000-black.mp4"
            with patch.object(widget, "process_clip", side_effect=widget.AuditRejectedError("rejected")), \
                 patch.object(widget, "black_clip", return_value=black) as fallback:
                self.assertEqual(widget.process_clip_or_black(0, clip, folder, "secret", deadline),
                                 (0, black, True))
            fallback.assert_called_once_with(0, clip, folder, deadline)
            # The task deadline is not something a black segment can paper over.
            with patch.object(widget, "process_clip", side_effect=TimeoutError("deadline")), \
                 self.assertRaises(TimeoutError):
                widget.process_clip_or_black(0, clip, folder, "secret", deadline)

    def test_prefers_video_result_over_preview_image(self):
        url = widget.video_result_url({"results": [
            {"url": "https://example.com/preview.png"},
            {"url": "https://example.com/output.mp4"},
        ]})
        self.assertEqual(url, "https://example.com/output.mp4")

    def test_takes_the_cleaned_clip_not_the_input_echo_or_comparison(self):
        # Real task 2110031279239163906 listed exactly these three videos.
        results = [
            {"url": "https://example.com/ser_00001.mp4", "nodeId": "283"},   # uploaded input
            {"url": "https://example.com/ver_00001.mp4", "nodeId": "183"},   # cleaned clip
            {"url": "https://example.com/T2V_00001.mp4", "nodeId": "210"},   # side-by-side
        ]
        self.assertEqual(widget.video_result_url({"results": results}), "https://example.com/ver_00001.mp4")
        # Without the known output node, any other node's video still beats the echoes.
        self.assertEqual(widget.video_result_url({"results": [
            results[0], {"url": "https://example.com/other.mp4", "nodeId": "999"}, results[2]]}),
            "https://example.com/other.mp4")
        with self.assertRaises(widget.GenerationFailedError):
            widget.video_result_url({"results": [results[0], results[2]]})

    def test_structured_audit_code_is_not_a_normal_failure(self):
        self.assertTrue(widget.is_audit_rejection({"errorCode": "CONTENT_AUDIT_REJECTED"}))
        self.assertFalse(widget.is_audit_rejection({"errorCode": "GPU_BUSY", "status": "FAILED"}))


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg/ffprobe required")
class VideoPipelineTests(unittest.TestCase):
    def make_video(self, path: Path, color: str, seconds: float) -> None:
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", f"color=c={color}:s=64x64:r=10:d={seconds}",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", str(path),
        ], check=True, capture_output=True)

    def pixel_at(self, path: Path, second: float) -> tuple[int, int, int]:
        result = subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path),
            "-ss", str(second), "-frames:v", "1", "-f", "rawvideo",
            "-pix_fmt", "rgb24", "-",
        ], check=True, capture_output=True)
        self.assertGreaterEqual(len(result.stdout), 3)
        return tuple(result.stdout[:3])

    def test_long_video_is_split_under_eight_seconds(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            source = folder / "source.mp4"
            self.make_video(source, "red", 17.1)
            deadline = time.monotonic() + 120
            clips = widget.split_video(source, folder, deadline)
            self.assertEqual(len(clips), 3)
            self.assertTrue(all(widget.probe_video(path, deadline)[0] <= 8.0 for path in clips))

    def test_eight_second_video_with_audio_stays_within_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            source = folder / "source.mp4"
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "color=c=red:s=64x64:r=10:d=8",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=8",
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
                "-shortest", str(source),
            ], check=True, capture_output=True)
            deadline = time.monotonic() + 120
            clips = widget.split_video(source, folder, deadline)
            self.assertTrue(all(widget.probe_video(path, deadline)[0] <= 8.0 for path in clips))
            self.assertTrue(all(widget.probe_video(path, deadline)[3] for path in clips))
            merged = widget.normalize_and_merge(clips, folder, deadline)
            merged_duration, _, _, merged_audio = widget.probe_video(merged, deadline)
            self.assertGreater(merged_duration, 7.5)
            self.assertTrue(merged_audio)

    def test_black_clip_matches_the_input_clip_and_merges(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            deadline = time.monotonic() + 120
            good = folder / "remote-0.mp4"
            self.make_video(good, "red", 0.5)
            lost = folder / "input-001.mp4"
            self.make_video(lost, "green", 0.5)
            black = widget.black_clip(1, lost, folder, deadline)
            duration, width, height, has_audio = widget.probe_video(black, deadline)
            self.assertAlmostEqual(duration, 0.5, delta=0.1)
            self.assertEqual((width, height, has_audio), (64, 64, True))
            merged = widget.normalize_and_merge([good, black], folder, deadline)
            red, dark = (self.pixel_at(merged, second) for second in (0.2, 0.7))
            self.assertGreater(red[0], 150)
            self.assertLess(max(dark), 40)

    def test_shorter_result_is_retimed_to_the_submitted_clip_length(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            short = folder / "remote-0.mp4"
            self.make_video(short, "red", 0.8)  # RunningHub returned 0.8 s for a 1.0 s input.
            deadline = time.monotonic() + 120
            merged = widget.normalize_and_merge([short], folder, deadline, target_durations=[1.0])
            self.assertAlmostEqual(widget.probe_video(merged, deadline)[0], 1.0, delta=0.08)

    def test_results_are_merged_in_given_order(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            clips = []
            for index, color in enumerate(("red", "green", "blue")):
                path = folder / f"remote-{index}.mp4"
                self.make_video(path, color, 0.5)
                clips.append(path)
            merged = widget.normalize_and_merge(clips, folder, time.monotonic() + 120)
            red, green, blue = (self.pixel_at(merged, second) for second in (0.2, 0.7, 1.2))
            self.assertGreater(red[0], max(red[1], red[2]) + 80)
            self.assertGreater(green[1], max(green[0], green[2]) + 40)
            self.assertGreater(blue[2], max(blue[0], blue[1]) + 80)


if __name__ == "__main__":
    unittest.main()
