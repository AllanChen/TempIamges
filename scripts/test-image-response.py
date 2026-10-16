"""Run the loader's response validation without building or launching Glance.

Usage: python3 scripts/test-image-response.py
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Glance/Sources/ImageLoader.swift").read_text()
helper = source[source.index("enum RemoteImageResponse {"):source.index("/// Persistent cache shared")]
tests = r'''
func check(_ label: String, _ condition: Bool) {
    guard condition else { fatalError(label) }
    print("ok: \(label)")
}
let html = Data("\u{feff}  <!DOCTYPE html><html>not an image</html>".utf8)
check("HTML body is rejected without MIME", RemoteImageResponse.isHTML(html))
check("HTML MIME is rejected with parameters", RemoteImageResponse.isHTML(Data("<!-- challenge -->".utf8), mimeType: "Text/HTML; charset=utf-8"))
check("XHTML MIME is rejected", RemoteImageResponse.isHTML(Data(), mimeType: "application/xhtml+xml"))
check("UTF16 HTML is rejected", RemoteImageResponse.isHTML("<html lang='en'>error</html>".data(using: .utf16)!))
check("PNG remains allowed", !RemoteImageResponse.isHTML(Data([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]), mimeType: "image/png"))
check("JPEG remains allowed", !RemoteImageResponse.isHTML(Data([0xff,0xd8,0xff,0xe0]), mimeType: "application/octet-stream"))
check("SVG remains allowed", !RemoteImageResponse.isHTML(Data("<?xml version='1.0'?><svg xmlns='http://www.w3.org/2000/svg'/>".utf8), mimeType: "image/svg+xml"))
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let legacy = directory.appendingPathComponent("legacy-cache")
try html.write(to: legacy)
check("legacy extensionless HTML cache is rejected", RemoteImageResponse.isHTMLFile(legacy))
let valid = directory.appendingPathComponent("image-cache")
try Data([0x89,0x50,0x4e,0x47]).write(to: valid)
check("binary cache remains allowed", !RemoteImageResponse.isHTMLFile(valid))
check("missing file is handled", !RemoteImageResponse.isHTMLFile(directory.appendingPathComponent("missing")))
'''
with tempfile.TemporaryDirectory(prefix="glance-image-response-") as directory:
    script = Path(directory) / "main.swift"
    script.write_text("import Foundation\n" + helper + tests)
    subprocess.run(["swift", "-module-cache-path", directory + "/modules", str(script), directory], check=True)
