"""Run the production diagnostic redactor without building or launching Glance."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / "Glance/Sources/Logger.swift").read_text()
redactor = source[source.index("    static func redact(_ input: String)"):]
tests = r'''
func check(_ name: String, _ condition: Bool) {
    precondition(condition, name)
    print("PASS: \(name)")
}
let samples = [
    "https://example.com/media.png?token=private-secret",
    "person@example.com",
    "GLG-ABCD-EFGH-JKLM-NPQR",
    "Authorization: Bearer private-secret",
    "token=private-secret",
    #"{"access_token":"private-secret","api_key":"private-key"}"#,
    "password='private password with spaces'",
    "/Users/someone/Downloads/private.png",
    "/private/var/folders/secret/input.png",
    "order_12345678-abcd-1234",
    "task_12345678-abcd-1234"
]
for sample in samples {
    let result = SupportDiagnostics.redact(sample)
    check("redacts " + String(sample.prefix(14)), result != sample && !result.contains("private-secret") && !result.contains("private-key") && !result.contains("password with spaces"))
}
let harmless = "Glance 1.0.2 (build 8)\nmacOS 15.6.1\nNetwork timed out; retry available."
check("preserves actionable non-sensitive context", SupportDiagnostics.redact(harmless) == harmless)
'''
with tempfile.TemporaryDirectory(prefix="glance-support-tests-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text("import Foundation\nenum SupportDiagnostics {\n" + redactor + tests)
    subprocess.run(["swift", str(path)], check=True, timeout=90)
