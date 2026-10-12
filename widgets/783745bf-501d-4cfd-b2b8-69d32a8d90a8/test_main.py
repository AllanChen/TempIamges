"""Local contract checks; never call the real vision-tasks endpoint."""

import importlib.util
import io
import json
import os
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

PARAMETERS = {"valid_token": "token", "team_id": 1, "team_creator_id": 2, "user_id": 3,
              "widget_name": "name", "prompt": "hello"}


class ProviderContractTests(unittest.TestCase):
    def test_payload_reads_parameters_and_falls_back_to_defaults(self):
        payload = widget.build_payload({"parameters": PARAMETERS})
        self.assertEqual(payload["widget_name"], "name")
        self.assertEqual(payload["task_params"], {"prompt": "hello"})
        with patch.dict(widget.os.environ, {}, clear=True):
            self.assertEqual(widget.build_payload({})["valid_token"],
                             widget.PARAMETER_DEFAULTS["valid_token"])
        with patch.dict(widget.os.environ, {"PPPRON_VALID_TOKEN": "env"}, clear=True):
            payload = widget.build_payload({})
        self.assertEqual((payload["valid_token"], payload["team_id"], payload["user_id"]), ("env", 2, 2001))

    def test_submit_sets_clip_url_and_does_not_retry(self):
        payload = widget.build_payload({"parameters": PARAMETERS})
        with patch.object(widget, "request_json", return_value={"success": True,
                          "result": {"task_uuid": "u1"}}) as request:
            self.assertEqual(widget.submit_task(payload, "https://x/clip.mp4", time.monotonic() + 60), "u1")
        self.assertFalse(request.call_args.kwargs["retry"])
        sent = request.call_args.args[0].data
        self.assertIn(b'"url": "https://x/clip.mp4"', sent)
        self.assertNotIn("url", payload["task_params"])

    def test_fetch_never_reuses_a_request_object(self):
        # With HTTPS_PROXY set, urllib rewrites a Request's scheme to http after the
        # first call; a reused object would then hit Cloudflare's 301 on every retry.
        seen = []

        def fake_urlopen(request, timeout):
            seen.append(request)
            if len(seen) < 3:
                raise widget.http.client.RemoteDisconnected("dropped")
            return io.BytesIO(b'{"ok": true}')

        original = widget.Request("https://api.pppron.com/vision-tasks/uuid/u1")
        with patch.object(widget, "urlopen", side_effect=fake_urlopen), patch.object(widget.time, "sleep"):
            self.assertEqual(widget.request_json(original, "task query", time.monotonic() + 60), {"ok": True})
        self.assertEqual(len({id(request) for request in seen}), 3)
        self.assertTrue(all(request is not original and request.type == "https" for request in seen))
        self.assertTrue(all(request.get_header("User-agent") == widget.USER_AGENT for request in seen))

    def test_wait_returns_url_and_raises_on_failure(self):
        done = {"success": True, "result": {"task_status": 3,
                "task_result": '{"url": "https://example.com/out.mp4"}'}}
        with patch.object(widget, "request_json", return_value=done):
            self.assertEqual(widget.wait_for_result("u1", time.monotonic() + 60),
                             "https://example.com/out.mp4")
        failed = {"success": True, "result": {"task_status": 4, "task_result": "{}"}}
        with patch.object(widget, "request_json", return_value=failed), \
             self.assertRaises(widget.TaskFailedError):
            widget.wait_for_result("u1", time.monotonic() + 60)


class ClipProcessingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.clip = self.folder / "clip.mp4"
        self.clip.write_bytes(b"video")
        patcher = patch.dict(os.environ, {"GLANCE_VIDEO_WIDGET_CACHE": str(self.folder / "cache")})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.payload = widget.build_payload({"parameters": PARAMETERS})

    def test_confirmed_failure_resubmits_and_caches_the_result(self):
        cache = widget.ClipCache(self.clip, 1)
        with patch.object(widget, "upload_video", return_value="https://temp.pppron.com/clip.mp4"), \
             patch.object(widget, "submit_task", side_effect=["u1", "u2"]) as submit, \
             patch.object(widget, "wait_for_result", side_effect=[
                 widget.TaskFailedError("gpu"), "https://temp.pppron.com/out.mp4"]), \
             patch.object(widget, "download_video", side_effect=lambda _url, path, *_: path), \
             patch.object(widget.time, "sleep"):
            index, path = widget.process_clip(0, self.clip, self.folder, self.payload, cache, time.monotonic() + 60)
        self.assertEqual((index, path.name), (0, "result-000.mp4"))
        self.assertEqual(submit.call_count, 2)
        self.assertEqual(cache.get(0), "https://temp.pppron.com/out.mp4")

    def test_cached_clip_skips_upload_and_submit(self):
        cache = widget.ClipCache(self.clip, 1)
        cache.put(0, "https://temp.pppron.com/cached.mp4")
        with patch.object(widget, "upload_video") as upload, \
             patch.object(widget, "submit_task") as submit, \
             patch.object(widget, "download_video", side_effect=lambda url, path, *_: path) as download:
            widget.process_clip(0, self.clip, self.folder, self.payload, cache, time.monotonic() + 60)
        upload.assert_not_called()
        submit.assert_not_called()
        self.assertEqual(download.call_args.args[0], "https://temp.pppron.com/cached.mp4")

    def test_unknown_submit_outcome_is_not_retried(self):
        cache = widget.ClipCache(self.clip, 1)
        with patch.object(widget, "upload_video", return_value="https://temp.pppron.com/clip.mp4"), \
             patch.object(widget, "submit_task", side_effect=RuntimeError("task submit failed")) as submit, \
             self.assertRaises(RuntimeError):
            widget.process_clip(0, self.clip, self.folder, self.payload, cache, time.monotonic() + 60)
        self.assertEqual(submit.call_count, 1)
        self.assertIsNone(cache.get(0))

    def test_main_returns_uploaded_merged_url(self):
        with patch.object(widget.shutil, "which", return_value="/usr/bin/ffmpeg"), \
             patch.object(widget, "split_video", return_value=[self.folder / "input-000.mp4"]), \
             patch.object(widget, "ClipCache"), \
             patch.object(widget, "process_clip", return_value=(0, self.folder / "result-000.mp4")), \
             patch.object(widget, "probe_video", return_value=(7.7, 64, 64, True)), \
             patch.object(widget, "normalize_and_merge", return_value=self.folder / "merged.mp4") as merge, \
             patch.object(widget, "restore_original_audio", return_value=self.folder / "result.mp4") as restore, \
             patch.object(widget, "upload_video", return_value="https://temp.pppron.com/result.mp4") as upload, \
             patch.dict(os.environ, {"GLANCE_TASK_OUTPUT_DIR": str(self.folder)}):
            result = widget.main({"input": {"path": str(self.clip)}, "parameters": PARAMETERS})
        self.assertEqual(result, {"outputs": [{"type": "video", "url": "https://temp.pppron.com/result.mp4"}]})
        self.assertEqual(merge.call_args.args[3], [7.7])  # Results are retimed to the submitted clip lengths.
        self.assertEqual(restore.call_args.args[1], self.clip)
        self.assertEqual(upload.call_args.args[0], self.folder / "result.mp4")


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg/ffprobe required")
class VideoPipelineTests(unittest.TestCase):
    def make_video(self, path: Path, color: str, seconds: float, audio: bool = False) -> None:
        command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                   "-f", "lavfi", "-i", f"color=c={color}:s=64x64:r=10:d={seconds}"]
        if audio:
            command += ["-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}", "-c:a", "aac"]
        command += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-shortest", str(path)]
        subprocess.run(command, check=True, capture_output=True)

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

    def test_results_are_merged_in_given_order_with_original_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            source = folder / "source.mp4"
            self.make_video(source, "white", 1.5, audio=True)
            clips = []
            for index, color in enumerate(("red", "green", "blue")):
                path = folder / f"remote-{index}.mp4"
                self.make_video(path, color, 0.5)  # Provider results carry no usable audio.
                clips.append(path)
            deadline = time.monotonic() + 120
            merged = widget.normalize_and_merge(clips, folder, deadline)
            result = widget.restore_original_audio(merged, source, folder, deadline)
            red, green, blue = (self.pixel_at(result, second) for second in (0.2, 0.7, 1.2))
            self.assertGreater(red[0], max(red[1], red[2]) + 80)
            self.assertGreater(green[1], max(green[0], green[2]) + 40)
            self.assertGreater(blue[2], max(blue[0], blue[1]) + 80)
            duration, _, _, has_audio = widget.probe_video(result, deadline)
            self.assertTrue(has_audio)
            self.assertAlmostEqual(duration, 1.5, delta=0.2)
            streams = json.loads(subprocess.run([
                "ffprobe", "-v", "error", "-show_entries", "stream=codec_type,sample_rate",
                "-of", "json", str(result)], check=True, capture_output=True, text=True).stdout)["streams"]
            self.assertEqual([s["sample_rate"] for s in streams if s["codec_type"] == "audio"], ["48000"])

    def test_stretched_result_is_retimed_to_the_submitted_clip_length(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            source = folder / "source.mp4"
            self.make_video(source, "white", 1.0, audio=True)
            slow = folder / "remote-0.mp4"
            self.make_video(slow, "red", 1.6)  # The provider returned 1.6 s for a 1.0 s input.
            deadline = time.monotonic() + 120
            merged = widget.normalize_and_merge([slow], folder, deadline, target_durations=[1.0])
            self.assertAlmostEqual(widget.probe_video(merged, deadline)[0], 1.0, delta=0.1)
            result = widget.restore_original_audio(merged, source, folder, deadline)
            duration, _, _, has_audio = widget.probe_video(result, deadline)
            self.assertAlmostEqual(duration, 1.0, delta=0.1)
            self.assertTrue(has_audio)

    def test_source_without_audio_merges_silently(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            source = folder / "source.mp4"
            self.make_video(source, "white", 1.0)
            clip = folder / "remote-0.mp4"
            self.make_video(clip, "red", 1.0)
            deadline = time.monotonic() + 120
            merged = widget.normalize_and_merge([clip], folder, deadline)
            result = widget.restore_original_audio(merged, source, folder, deadline)
            self.assertFalse(widget.probe_video(result, deadline)[3])


if __name__ == "__main__":
    unittest.main()
