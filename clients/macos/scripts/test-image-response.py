"""Run the loader's response validation without building or launching Glance.

Usage: python3 clients/macos/scripts/test-image-response.py
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Glance/Sources/ImageLoader.swift").read_text()
helper = source[source.index("enum RemoteImageResponse {"):source.index("/// Persistent cache shared")]
dialog_source = (root / "Glance/Sources/Inspect/ImageCompressionDialog.swift").read_text()
resize_plan = dialog_source[dialog_source.index("enum ImageResizePlan {"):dialog_source.index("enum CompressionSizeEstimate {")]
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
let half = ImageResizePlan.dimensions(sourceWidth: 1000, sourceHeight: 500, scale: 0.5)!
check("resize preserves the aspect ratio", half.width == 500 && half.height == 250)
let rounded = ImageResizePlan.dimensions(sourceWidth: 101, sourceHeight: 51, scale: 0.5)!
check("resize rounds both dimensions from the same scale", rounded.width == 51 && rounded.height == 26)
let reduced = ImageResizePlan.dimensions(sourceWidth: 100, sourceHeight: 100, scale: 0.99)!
check("resize allows a one percent reduction", reduced.width == 99 && reduced.height == 99)
check("resize rejects 100 percent", ImageResizePlan.dimensions(sourceWidth: 100, sourceHeight: 100, scale: 1) == nil)
check("resize rejects enlargement", ImageResizePlan.dimensions(sourceWidth: 100, sourceHeight: 100, scale: 1.1) == nil)
check("resize rejects zero and negative scales", ImageResizePlan.dimensions(sourceWidth: 100, sourceHeight: 100, scale: 0) == nil && ImageResizePlan.dimensions(sourceWidth: 100, sourceHeight: 100, scale: -0.5) == nil)
check("resize rejects an unchanged one pixel image", ImageResizePlan.dimensions(sourceWidth: 1, sourceHeight: 1, scale: 0.5) == nil)
let narrow = ImageResizePlan.dimensions(sourceWidth: 2, sourceHeight: 1, scale: 0.5)!
check("resize allows at least one dimension to shrink", narrow.width == 1 && narrow.height == 1)
check("resize size estimate follows the pixel-area ratio", ImageResizePlan.estimatedByteCount(sourceByteCount: 1_000_000, scale: 0.5) == 250_000)
check("resize size estimate stays positive at the minimum scale", ImageResizePlan.estimatedByteCount(sourceByteCount: 1, scale: 0.01) == 1)
'''
with tempfile.TemporaryDirectory(prefix="glance-image-response-") as directory:
    script = Path(directory) / "main.swift"
    script.write_text("import Foundation\n" + helper + resize_plan + tests)
    subprocess.run(["swift", "-module-cache-path", directory + "/modules", str(script), directory], check=True)
