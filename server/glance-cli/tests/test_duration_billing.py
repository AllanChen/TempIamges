import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

from glance_cli.runtime import verify_billing_input, execute


class DurationBillingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'input.mp4'
        self.source.write_bytes(b'actual-video-bytes')
        self.task = {'taskId': 'task_1', 'claimToken': 'claim-token',
                     'input': {'path': str(self.source)},
                     'parameters': {'_billingQuote': {'mode': 'duration'}}}

    def probe(self, seconds='60'):
        return subprocess.CompletedProcess([], 0, json.dumps({'streams': [{'duration': seconds}], 'format': {'duration': '61'}}), '')

    @patch('glance_cli.runtime.request', return_value={'verified': True})
    @patch('glance_cli.runtime.subprocess.run')
    def test_sends_actual_bytes_and_video_stream_duration(self, probe, request):
        probe.return_value = self.probe()
        verify_billing_input(self.task, deadline=time.monotonic()+60)
        args, kwargs = request.call_args
        self.assertEqual(args[1], '/api/v2/widget-tasks/task_1/verify-input')
        self.assertEqual(args[2], {'durationSeconds': 60, 'byteSize': 18,
                         'sha256': hashlib.sha256(b'actual-video-bytes').hexdigest()})
        self.assertEqual(kwargs['headers'], {'X-Task-Claim': 'claim-token'})

    @patch('glance_cli.runtime.request', return_value={'verified': True})
    @patch('glance_cli.runtime.subprocess.run')
    def test_container_duration_fallback(self, probe, request):
        probe.return_value = self.probe('N/A')
        verify_billing_input(self.task, deadline=time.monotonic()+60)
        self.assertEqual(request.call_args.args[2]['durationSeconds'], 61)

    @patch('glance_cli.runtime.request')
    @patch('glance_cli.runtime.subprocess.run')
    def test_invalid_duration_never_reaches_verification(self, probe, request):
        for value in ['0', '-1', 'NaN', 'Infinity']:
            probe.return_value = self.probe(value)
            with self.assertRaises(ValueError):
                verify_billing_input(self.task, deadline=time.monotonic()+60)
        request.assert_not_called()

    @patch('glance_cli.runtime.request')
    @patch('glance_cli.runtime.subprocess.run')
    def test_fixed_tasks_do_not_probe_or_call_verification(self, probe, request):
        verify_billing_input({'parameters': {}}, deadline=time.monotonic()+60)
        probe.assert_not_called()
        request.assert_not_called()

    @patch('glance_cli.runtime.subprocess.Popen')
    @patch('glance_cli.runtime.request', return_value={'verified': False})
    @patch('glance_cli.runtime.subprocess.run')
    def test_rejection_stops_before_widget_process_starts(self, probe, request, process):
        probe.return_value = self.probe()
        (self.root / 'main.py').write_text('def main(task): return {}')
        with self.assertRaisesRegex(ValueError, 'verification was not accepted'):
            with execute(self.root, self.task, download_input=False):
                self.fail('Widget execution must not be reached')
        process.assert_not_called()

    @patch('glance_cli.runtime.subprocess.Popen')
    @patch('glance_cli.runtime.request', side_effect=RuntimeError('offline'))
    @patch('glance_cli.runtime.subprocess.run')
    def test_verification_network_failure_does_not_start_paid_work(self, probe, request, process):
        probe.return_value = self.probe()
        (self.root / 'main.py').write_text('def main(task): return {}')
        with self.assertRaisesRegex(RuntimeError, 'offline'):
            with execute(self.root, self.task, download_input=False):
                self.fail('Widget execution must not be reached')
        process.assert_not_called()
