"""Turn a failed Widget run into the error code and reason the user sees.

A provider safety-review rejection is something the user can fix (change the
input), so it gets its own code and a normalized category instead of the
generic ``worker_error``. Only category names leave this machine; provider text
and tracebacks stay in the worker's ``message`` for operators.
"""
import re

from .runtime import TaskTimeoutError

# Only the exception's final line is read. Traceback source lines mention
# helpers such as ``is_audit_rejection`` and must not count as a rejection.
_FINAL_LINE = re.compile(r"^(?:[\w.]+\.)?(\w*(?:Error|Exception)): ?(.*)$")
_CONTENT_TERMS = (
    "rhauditexception", "content rejected", "content moderation", "content audit",
    "porn", "nsfw", "political content", "内容审核", "审核未通过", "审核拒绝",
    "色情", "涉黄", "涉政",
)
_SEXUAL_TERMS = ("porn", "nsfw", "sexual", "色情", "涉黄")
_POLITICAL_TERMS = ("political", "涉政", "政治")


def classify_failure(error: BaseException) -> tuple[str, str | None]:
    """Return ``(errorCode, reason)``; reason is ``sexual``, ``political``, ``other`` or None."""
    if isinstance(error, TaskTimeoutError):
        return "worker_timeout", None
    lines = [line.strip() for line in str(error).splitlines() if line.strip()]
    final = next((match for match in map(_FINAL_LINE.match, reversed(lines)) if match), None)
    if final is None:
        return "worker_error", None
    name, message = final.group(1), final.group(2).lower()
    if name != "AuditRejectedError" and not any(term in message for term in _CONTENT_TERMS):
        return "worker_error", None
    if any(term in message for term in _SEXUAL_TERMS):
        return "content_rejected", "sexual"
    if any(term in message for term in _POLITICAL_TERMS):
        return "content_rejected", "political"
    return "content_rejected", "other"
