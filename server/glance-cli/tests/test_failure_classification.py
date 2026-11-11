"""Failure classification runs real widget processes; no network, no real accounts."""

from pathlib import Path
import sys
import tempfile
import unittest

from glance_cli.failures import classify_failure
from glance_cli.runtime import TaskTimeoutError, execute


def run_widget(source: str) -> BaseException:
    """Run ``source`` as a widget's main.py through the real runner and return its failure."""
    with tempfile.TemporaryDirectory() as folder:
        (Path(folder) / "main.py").write_text(source, encoding="utf-8")
        try:
            with execute(Path(folder), {}, timeout=30, download_input=False, python_path=sys.executable):
                pass
        except Exception as error:  # the runner reports a widget failure as an exception
            return error
    raise AssertionError("widget unexpectedly succeeded")


class FailureClassificationTests(unittest.TestCase):
    def test_audit_rejection_from_a_real_widget_is_content_rejected(self):
        error = run_widget(
            "class AuditRejectedError(RuntimeError):\n    pass\n"
            "def is_audit_rejection(result):\n    return True\n"
            "def main(task):\n"
            "    if is_audit_rejection({}):\n"
            "        raise AuditRejectedError('RunningHub content rejected: Porn')\n")
        self.assertEqual(classify_failure(error), ("content_rejected", "sexual"))

    def test_categories_and_wrapped_messages(self):
        cases = {
            "AuditRejectedError: RunningHub content rejected: Political content": ("content_rejected", "political"),
            "RuntimeError: 内容审核未通过，请修改输入 / Content rejected; please revise the input.": ("content_rejected", "other"),
            "Exception: RunningHub task failed: audit.RHAuditException 涉黄 (status=FAILED)": ("content_rejected", "sexual"),
            "AuditRejectedError: rejected": ("content_rejected", "other"),
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(classify_failure(RuntimeError("Traceback (most recent call last):\n  ...\n" + text)), expected)

    def test_helper_names_in_traceback_source_lines_do_not_count(self):
        error = run_widget(
            "def is_audit_rejection(result):\n    return False\n"
            "def main(task):\n"
            "    if not is_audit_rejection({}):\n"
            "        raise RuntimeError('RunningHub upload failed: HTTP 502')\n")
        self.assertEqual(classify_failure(error), ("worker_error", None))

    def test_other_failures_keep_their_codes(self):
        self.assertEqual(classify_failure(TaskTimeoutError("too slow")), ("worker_timeout", None))
        self.assertEqual(classify_failure(RuntimeError("connection reset")), ("worker_error", None))


if __name__ == "__main__":
    unittest.main()
