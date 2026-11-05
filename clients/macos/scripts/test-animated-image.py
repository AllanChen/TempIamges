"""Headless decoder/import regression checks. Does not build or launch Glance.
Optional argument: an actual animated image file (including extensionless files).
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
loader = (root / 'Glance/Sources/ImageLoader.swift').read_text()
decode = loader[loader.index('    static func decodeWithImageIO(from url:'):]
decode = decode[:decode.index('    private func decodeLocalImage(')]
resize = loader[loader.index('    private func resizeImage('):loader.index('    private func cacheOriginal(')].replace('private func', 'func', 1)
tests = r'''
func check(_ label: String, _ value: Bool) {
    precondition(value, label)
    print("PASS: \(label)")
}
func fixture(type: CFString, count: Int, loop: Int? = 0) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type, count, nil)!
    let png = type as String == "public.png"
    let dict = png ? kCGImagePropertyPNGDictionary : kCGImagePropertyGIFDictionary
    let loopKey = png ? kCGImagePropertyAPNGLoopCount : kCGImagePropertyGIFLoopCount
    let delayKey = png ? kCGImagePropertyAPNGDelayTime : kCGImagePropertyGIFDelayTime
    if let loop { CGImageDestinationSetProperties(destination, [dict: [loopKey: loop]] as CFDictionary) }
    for index in 0..<count {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: index == 0 ? 1 : 0, green: index == 1 ? 1 : 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        CGImageDestinationAddImage(destination, context.makeImage()!, [dict: [delayKey: index == 0 ? 0.06 : 0.12]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}
let gif = fixture(type: UTType.gif.identifier as CFString, count: 2)
let image = DecodeHarness.decodeWithImageIO(data: gif, maxPixel: 4)!
let animation = image.glanceAnimation!
check("GIF frames retained through thumbnail decoding", animation.frameCount == 2)
check("GIF infinite looping preserved", animation.totalPlays == nil)
check("per-frame delays preserved", abs(animation.delays[0] - 0.06) < 0.001 && abs(animation.delays[1] - 0.12) < 0.001)
check("preview resizing does not flatten animation", DecodeHarness().resizeImage(image, maxDimension: 4) === image)
let first = animation.frame(at: 0)!.dataProvider!.data! as Data
let second = animation.frame(at: 1)!.dataProvider!.data! as Data
check("decoded frames visibly differ", first != second)
check("invalid frame rejected", animation.frame(at: 2) == nil)
let finite = ImageAnimation(data: fixture(type: UTType.gif.identifier as CFString, count: 2, loop: 1))!
check("GIF repeat count becomes total plays", finite.totalPlays == 2)
let png = fixture(type: UTType.png.identifier as CFString, count: 1)
check("static PNG stays static", DecodeHarness.decodeWithImageIO(data: png, maxPixel: nil)?.glanceAnimation == nil)
let apng = ImageAnimation(data: fixture(type: UTType.png.identifier as CFString, count: 2, loop: 2))!
check("APNG frames and total plays", apng.frameCount == 2 && apng.totalPlays == 2)
check("APNG delays", abs(apng.delays[0] - 0.06) < 0.001)
let tiff = fixture(type: UTType.tiff.identifier as CFString, count: 2)
check("multipage TIFF is not animation", ImageAnimation(data: tiff) == nil)
check("invalid bytes rejected", AnimatedImage.decode(data: Data("not an image".utf8)) == nil)
let saved = ClipboardImageImport.materialize(data: gif)!
defer { try? FileManager.default.removeItem(at: saved) }
check("clipboard retains exact GIF bytes", try Data(contentsOf: saved) == gif)
check("clipboard uses actual format extension", saved.pathExtension == "gif")
check("cached/local image still animates", DecodeHarness.decodeWithImageIO(from: saved, maxPixel: nil)?.glanceAnimation?.frameCount == 2)
if CommandLine.arguments.count > 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let original = try Data(contentsOf: url)
    let remote = DecodeHarness.decodeWithImageIO(data: original, maxPixel: nil)!.glanceAnimation!
    let local = DecodeHarness.decodeWithImageIO(from: url, maxPixel: 800)!.glanceAnimation!
    check("supplied extensionless image retains all frames", remote.frameCount == 80 && local.frameCount == 80)
    check("supplied GIF is infinite", remote.totalPlays == nil)
    check("supplied GIF frames change", (remote.frame(at: 0)!.dataProvider!.data! as Data) != (remote.frame(at: 20)!.dataProvider!.data! as Data))
    print("Supplied GIF: \(remote.frameCount) frames; \(remote.delays.reduce(0, +)) seconds per loop")
}
'''
with tempfile.TemporaryDirectory(prefix='glance-animation-tests-') as directory:
    main = Path(directory) / 'main.swift'
    main.write_text('import AppKit\nimport ImageIO\nimport UniformTypeIdentifiers\nclass DecodeHarness {\n' + decode + resize + '\n}\n' + tests)
    binary = str(Path(directory) / 'test')
    subprocess.run(['swiftc', '-module-cache-path', directory + '/modules', str(root / 'Glance/Sources/AnimatedImage.swift'), str(main), '-o', binary], check=True)
    subprocess.run([binary] + sys.argv[1:], check=True)
