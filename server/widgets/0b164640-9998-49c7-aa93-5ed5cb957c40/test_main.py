import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import URLError

from PIL import Image
import main as widget


class RemoveObjectsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.input = self.directory / 'input.png'
        Image.new('RGB', (64, 64), 'blue').save(self.input)
        self.image_bytes = self.input.read_bytes()
        self.task = {'input': {'path': str(self.input)}, 'parameters': {'prompt': 'Remove the red ball on the right'}}
        self.env = patch.dict(os.environ, RUNNINGHUB_API_KEY='secret-test-key', GLANCE_TASK_OUTPUT_DIR=str(self.directory))
        self.env.start()
        self.addCleanup(self.env.stop)

    def run_replies(self, replies, output=None):
        seen = []
        def fake_open(request, timeout):
            self.assertGreater(timeout, 0)
            self.assertLessEqual(timeout, 60)
            seen.append(request)
            if request.full_url == 'https://example.com/result.png':
                return io.BytesIO(self.image_bytes if output is None else output)
            value = replies.pop(0)
            if isinstance(value, Exception):
                raise value
            return io.BytesIO(json.dumps(value).encode())
        self.seen = seen
        with patch.object(widget, 'urlopen', side_effect=fake_open), patch.object(widget.time, 'sleep'):
            return widget.main(self.task)

    def success(self):
        return {'status': 'SUCCESS', 'results': [{'url': 'https://example.com/result.png'}]}

    def initial(self):
        return [{'code': 0, 'data': {'fileName': 'uploaded/actual.png'}}, {'taskId': 'task-1'}]

    def test_prompt_image_mapping_and_output(self):
        for prompt in ('Remove the red ball on the right', 'the person on the left'):
            with self.subTest(prompt=prompt):
                self.task['parameters']['prompt'] = prompt
                result = self.run_replies(self.initial() + [self.success()])
                payload = json.loads(self.seen[1].data)
                self.assertEqual(payload['nodeInfoList'], [
                    {'nodeId':'6','fieldName':'text','fieldValue':widget.build_prompt(prompt),'description':'text'},
                    {'nodeId':'191','fieldName':'image','fieldValue':'uploaded/actual.png','description':'image'}])
                self.assertEqual(payload['instanceType'], 'default')
                self.assertEqual(payload['usePersonalQueue'], 'false')
                self.assertEqual(self.seen[1].full_url, 'https://www.runninghub.cn/openapi/v2/run/ai-app/2117102824717897730')
                self.assertEqual(self.seen[1].get_header('Authorization'), 'Bearer secret-test-key')
                self.assertIn(self.image_bytes, self.seen[0].data)
                output = Path(result['outputs'][0]['path'])
                self.assertTrue(output.is_absolute())
                with Image.open(output) as image:
                    image.verify()
                self.assertEqual(result['outputs'][0]['type'], 'image')

    def test_missing_blank_or_invalid_prompt_never_uploads(self):
        for prompt in (None, '', '   ', 123, 'x' * 2001):
            self.task['parameters']['prompt'] = prompt
            with patch.object(widget, 'urlopen') as request, self.assertRaises(ValueError):
                widget.main(self.task)
            request.assert_not_called()

    def test_chinese_prompt_shows_bilingual_error_without_upload(self):
        self.task['parameters']['prompt'] = '移除红球'
        with patch.object(widget, 'urlopen') as request, self.assertRaisesRegex(ValueError, '请使用英文.*in English'):
            widget.main(self.task)
        request.assert_not_called()

    def test_multiple_images_rejected_before_upload(self):
        self.task['input']['imagePaths'] = [str(self.input)] * 2
        with patch.object(widget, 'urlopen') as request, self.assertRaises(ValueError):
            widget.main(self.task)
        request.assert_not_called()

    def test_corrupt_input_rejected_before_upload(self):
        self.input.write_text('not an image')
        with patch.object(widget, 'urlopen') as request, self.assertRaises(ValueError):
            widget.main(self.task)
        request.assert_not_called()

    def test_query_network_error_retries_same_task(self):
        self.run_replies(self.initial() + [URLError('temporary'), self.success()])
        self.assertEqual(sum(r.full_url == widget.RUN_URL for r in self.seen), 1)
        queries = [json.loads(r.data) for r in self.seen if r.full_url == widget.QUERY_URL]
        self.assertEqual(queries, [{'taskId':'task-1'}] * 2)

    def test_submit_timeout_never_resubmits(self):
        with self.assertRaises(RuntimeError):
            self.run_replies([self.initial()[0], TimeoutError('unknown submission status')])
        self.assertEqual(sum(r.full_url == widget.RUN_URL for r in self.seen), 1)

    def test_content_rejection_never_retries(self):
        for error in ({'failedReason':{'exception_type':'RhAuditException'}}, {'errorMessage':'Porn'}, {'errorMessage':'涉政内容拒绝'}):
            with self.assertRaisesRegex(RuntimeError, 'Content rejected'):
                self.run_replies(self.initial() + [{'status':'FAILED', **error}])
            self.assertEqual(sum(r.full_url == widget.RUN_URL for r in self.seen), 1)

    def test_confirmed_generation_failure_has_three_attempt_limit(self):
        replies = [self.initial()[0]]
        for n in range(3):
            replies += [{'taskId': f'task-{n}'}, {'status':'FAILED','errorMessage':'GPU unavailable'}]
        with self.assertRaises(RuntimeError):
            self.run_replies(replies)
        self.assertEqual(sum(r.full_url == widget.RUN_URL for r in self.seen), 3)
        self.assertEqual(sum(r.full_url == widget.UPLOAD_URL for r in self.seen), 1)

    def test_invalid_result_is_not_success(self):
        with self.assertRaises(RuntimeError):
            self.run_replies(self.initial() + [self.success()], output=b'<html>Error</html>')
        self.assertFalse(list(self.directory.glob('*.part')))
        self.assertEqual(sum(r.full_url == widget.RUN_URL for r in self.seen), 1)

    def test_shared_deadline_stops_without_network(self):
        with patch.object(widget.time, 'monotonic', side_effect=[0, 901]), patch.object(widget, 'urlopen') as request:
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                widget.main(self.task)
        request.assert_not_called()

    def test_provider_error_redacts_key(self):
        with self.assertRaises(RuntimeError) as error:
            self.run_replies([self.initial()[0], {'errorMessage':'secret-test-key'}])
        self.assertNotIn('secret-test-key', str(error.exception))
        self.assertIn('[REDACTED]', str(error.exception))

    def test_manifest_price_and_languages(self):
        manifest = json.loads(Path(__file__).with_name('widget.json').read_text())
        self.assertEqual(manifest['creditCost'], 30)
        self.assertEqual(manifest['name'], '移除物体')
        self.assertEqual(manifest['localizations']['en']['name'], 'Remove Objects')
        command = manifest['commands'][0]
        self.assertEqual(command['inputTypes'], ['image'])
        self.assertEqual(command['parameterSchema']['required'], ['prompt'])
        self.assertEqual(command['outputs'], ['image'])


if __name__ == '__main__':
    unittest.main()
