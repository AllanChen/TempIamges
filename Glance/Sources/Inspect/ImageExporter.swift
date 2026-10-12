import AppKit
import UniformTypeIdentifiers
import ImageIO
import libwebp

/// Immutable snapshot of what ⌘S should render. Rendering happens on the
/// background queue so large compare images never block the main thread.
enum QuickSaveSource {
    case single(NSImage, Int)
    case sideBySide(NSImage, Int, NSImage, Int)
    case slider(NSImage, Int, NSImage, Int, CGFloat)

    func render() -> CGImage? {
        switch self {
        case .single(let image, let rotation):
            return ImageExporter.cgImage(from: image, rotatedQuarters: rotation)
        case .sideBySide(let a, let aRotation, let b, let bRotation):
            guard let aCG = ImageExporter.cgImage(from: a, rotatedQuarters: aRotation),
                  let bCG = ImageExporter.cgImage(from: b, rotatedQuarters: bRotation) else { return nil }
            return ImageExporter.sideBySide(a: aCG, b: bCG)
        case .slider(let a, let aRotation, let b, let bRotation, let fraction):
            guard let aCG = ImageExporter.cgImage(from: a, rotatedQuarters: aRotation),
                  let bCG = ImageExporter.cgImage(from: b, rotatedQuarters: bRotation) else { return nil }
            return ImageExporter.slider(a: aCG, b: bCG, fraction: fraction)
        }
    }
}

enum ImageExportFormat {
    case png, jpeg, webP, heic, tiff, gif, icns

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .webP: return UTType("org.webmproject.webp") ?? .png
        case .heic: return .heic
        case .tiff: return .tiff
        case .gif: return .gif
        case .icns: return UTType("com.apple.icns")!
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .webP: return "webp"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .gif: return "gif"
        case .icns: return "icns"
        }
    }
}

/// Encodes an NSImage to disk. ImageIO handles PNG/JPEG/ICNS; libwebp handles
/// WebP because macOS ships a WebP decoder but no ImageIO WebP destination.
/// Never mutates the source file.
enum ImageExporter {
    static func write(image: NSImage, rotatedQuarters: Int, to url: URL,
                      format: ImageExportFormat) -> Bool {
        guard let output = cgImage(from: image, rotatedQuarters: rotatedQuarters) else { return false }
        return write(cgImage: output, to: url, format: format)
    }

    static func cgImage(from image: NSImage, rotatedQuarters: Int) -> CGImage? {
        guard let image = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let quarters = ((rotatedQuarters % 4) + 4) % 4
        guard quarters != 0 else { return image }
        return rotate(image, quarters: quarters)
    }

    static func write(cgImage: CGImage, to url: URL, format: ImageExportFormat,
                      quality: CGFloat = 0.9) -> Bool {
        if format == .icns {
            return writeIcon(cgImage: cgImage, to: url)
        }
        guard let data = encodedData(cgImage: cgImage, format: format, quality: quality) else { return false }
        return write(data: data, to: url)
    }

    static func writeCompressed(cgImage: CGImage, to url: URL, format: ImageExportFormat,
                                quality: CGFloat, targetByteCount: Int64,
                                allowResizing: Bool) -> Bool {
        let target = max(1_024, targetByteCount)
        var image = cgImage
        guard var data = compressedData(cgImage: image, format: format,
                                        quality: quality, targetByteCount: target) else { return false }

        // Only the unchecked dimension option allows resizing. Width and height
        // always use the same scale, so the source aspect ratio cannot change.
        for _ in 0..<(allowResizing ? 6 : 0) where Int64(data.count) > Int64(Double(target) * 1.08) {
            let ratio = sqrt(Double(target) / Double(data.count))
            let scale = max(0.35, min(0.98, ratio * 0.98))
            let width = max(1, Int((Double(image.width) * scale).rounded()))
            let height = max(1, Int((Double(image.height) * scale).rounded()))
            guard width < image.width || height < image.height,
                  let resized = resized(image, width: width, height: height),
                  let resizedData = compressedData(cgImage: resized, format: format,
                                                   quality: quality, targetByteCount: target) else { break }
            image = resized
            data = resizedData
        }

        return write(data: data, to: url)
    }

    private static func compressedData(cgImage: CGImage, format: ImageExportFormat,
                                       quality: CGFloat, targetByteCount: Int64) -> Data? {
        switch format {
        case .jpeg, .heic, .webP:
            return lossyData(cgImage: cgImage, format: format,
                             maximumQuality: quality, targetByteCount: targetByteCount)
        case .png, .tiff, .gif:
            return quantizedData(cgImage: cgImage, format: format,
                                 quality: quality, targetByteCount: targetByteCount)
        case .icns:
            return nil
        }
    }

    private static func lossyData(cgImage: CGImage, format: ImageExportFormat,
                                  maximumQuality: CGFloat, targetByteCount: Int64) -> Data? {
        let maxQuality = max(0.03, min(1, maximumQuality))
        guard var smallest = encodedData(cgImage: cgImage, format: format,
                                         quality: maxQuality) else { return nil }
        let upperBound = Int64(Double(targetByteCount) * 1.08)
        guard Int64(smallest.count) > upperBound else { return smallest }

        // Find the highest usable encoding quality that reaches the displayed
        // size target while preserving the original pixel dimensions.
        var low: CGFloat = 0.03
        var high = maxQuality
        var best: Data?
        for _ in 0..<8 {
            let candidateQuality = (low + high) / 2
            guard let candidate = encodedData(cgImage: cgImage, format: format,
                                              quality: candidateQuality) else { break }
            if candidate.count < smallest.count { smallest = candidate }
            if Int64(candidate.count) <= upperBound {
                best = candidate
                low = candidateQuality
            } else {
                high = candidateQuality
            }
        }
        return best ?? smallest
    }

    private static func quantizedData(cgImage: CGImage, format: ImageExportFormat,
                                      quality: CGFloat, targetByteCount: Int64) -> Data? {
        let upperBound = Int64(Double(targetByteCount) * 1.08)
        let startingBits = max(2, min(8, Int((quality * 7).rounded()) + 1))
        var smallest: Data?

        // PNG/TIFF/GIF ignore lossy quality. Reduce color precision instead;
        // dimensions and aspect ratio remain exactly unchanged.
        for bits in stride(from: startingBits, through: 2, by: -1) {
            guard let image = quantized(cgImage, bitsPerChannel: bits),
                  let data = encodedData(cgImage: image, format: format, quality: quality) else { continue }
            if smallest.map({ data.count < $0.count }) ?? true { smallest = data }
            if Int64(data.count) <= upperBound { return data }
        }
        return smallest
    }

    private static func encodedData(cgImage: CGImage, format: ImageExportFormat,
                                    quality: CGFloat) -> Data? {
        if format == .webP {
            return webPData(cgImage: cgImage, quality: quality)
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, format.utType.identifier as CFString, 1, nil
        ) else { return nil }
        var properties: [CFString: Any] = [:]
        if format == .jpeg || format == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        } else if format == .tiff {
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5]
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func webPData(cgImage: CGImage, quality: CGFloat) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0, width <= 16_383, height <= 16_383 else {
            Logger.error("WebP export rejected unsupported dimensions: \(width) × \(height)")
            return nil
        }

        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            Logger.error("WebP export could not create an RGBA bitmap context")
            return nil
        }

        // Core Graphics renders premultiplied RGBA. libwebp expects straight
        // alpha, so restore RGB at translucent edges before encoding.
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Int(rgba[offset + 3])
            guard alpha > 0, alpha < 255 else { continue }
            rgba[offset] = UInt8(min(255, Int(rgba[offset]) * 255 / alpha))
            rgba[offset + 1] = UInt8(min(255, Int(rgba[offset + 1]) * 255 / alpha))
            rgba[offset + 2] = UInt8(min(255, Int(rgba[offset + 2]) * 255 / alpha))
        }

        var output: UnsafeMutablePointer<UInt8>?
        let encodedSize = rgba.withUnsafeBufferPointer { pixels in
            WebPEncodeRGBA(
                pixels.baseAddress,
                Int32(width),
                Int32(height),
                Int32(bytesPerRow),
                Float(max(0, min(1, quality)) * 100),
                &output
            )
        }
        guard encodedSize > 0, let output else {
            Logger.error("libwebp failed to encode the image")
            return nil
        }
        defer { WebPFree(output) }
        return Data(bytes: output, count: encodedSize)
    }

    private static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = makeContext(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func quantized(_ image: CGImage, bitsPerChannel: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
        return rgba.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            let shift = max(0, 8 - bitsPerChannel)
            let mask = UInt8(truncatingIfNeeded: 0xFF << shift)
            guard shift > 0 else { return context.makeImage() }
            let pixels = bytes.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: pixels.count, by: 4) {
                pixels[offset] &= mask
                pixels[offset + 1] &= mask
                pixels[offset + 2] &= mask
            }
            return context.makeImage()
        }
    }

    private static func write(data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            Logger.error("Image export failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Build a multi-resolution macOS icon. Every representation is square;
    /// non-square sources are aspect-fitted on a transparent canvas so the
    /// artwork is never stretched or cropped.
    private static func writeIcon(cgImage: CGImage, to url: URL) -> Bool {
        // The duplicate pixel sizes are distinct 1x/2x icon representations.
        // ImageIO uses 144 DPI to identify Retina entries; without it, the
        // 64px and 1024px representations are silently omitted from the ICNS.
        let representations = [
            (side: 16, dpi: 72),
            (side: 32, dpi: 144), (side: 32, dpi: 72),
            (side: 64, dpi: 144),
            (side: 128, dpi: 72),
            (side: 256, dpi: 144), (side: 256, dpi: 72),
            (side: 512, dpi: 144), (side: 512, dpi: 72),
            (side: 1024, dpi: 144),
        ]
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            ImageExportFormat.icns.utType.identifier as CFString,
            representations.count,
            nil
        ) else { return false }

        for representation in representations {
            let side = representation.side
            guard let context = makeContext(width: side, height: side) else { return false }
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .high
            drawAspectFit(cgImage,
                          in: CGRect(x: 0, y: 0, width: side, height: side),
                          context: context)
            guard let outputImage = context.makeImage() else { return false }
            let properties: [CFString: Any] = [
                kCGImagePropertyDPIWidth: representation.dpi,
                kCGImagePropertyDPIHeight: representation.dpi,
            ]
            CGImageDestinationAddImage(destination, outputImage, properties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }

    static func sideBySide(a: CGImage, b: CGImage) -> CGImage? {
        var height = min(4096, CGFloat(max(a.height, b.height)))
        var aWidth = CGFloat(a.width) * height / CGFloat(a.height)
        var bWidth = CGFloat(b.width) * height / CGFloat(b.height)
        let gap: CGFloat = 2
        if aWidth + bWidth + gap > 8192 {
            let scale = (8192 - gap) / (aWidth + bWidth)
            height *= scale
            aWidth *= scale
            bWidth *= scale
        }
        let width = aWidth + gap + bWidth
        guard let context = makeContext(width: Int(ceil(width)), height: Int(ceil(height))) else { return nil }
        fillCanvas(context, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(a, in: CGRect(x: 0, y: 0, width: aWidth, height: height))
        context.draw(b, in: CGRect(x: aWidth + gap, y: 0, width: bWidth, height: height))
        return context.makeImage()
    }

    static func slider(a: CGImage, b: CGImage, fraction: CGFloat) -> CGImage? {
        let rawWidth = CGFloat(max(a.width, b.width))
        let rawHeight = CGFloat(max(a.height, b.height))
        let scale = min(1, 4096 / max(rawWidth, rawHeight))
        let width = max(1, ceil(rawWidth * scale))
        let height = max(1, ceil(rawHeight * scale))
        guard let context = makeContext(width: Int(width), height: Int(height)) else { return nil }
        fillCanvas(context, width: width, height: height)
        context.interpolationQuality = .high
        drawAspectFit(a, in: CGRect(x: 0, y: 0, width: width, height: height), context: context)
        let split = max(0, min(1, fraction)) * width
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: split, height: height))
        drawAspectFit(b, in: CGRect(x: 0, y: 0, width: width, height: height), context: context)
        context.restoreGState()
        context.setFillColor(PanelStyle.textPrimary.withAlphaComponent(0.82).cgColor)
        context.fill(CGRect(x: max(0, split - 1), y: 0, width: 2, height: height))
        return context.makeImage()
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func fillCanvas(_ context: CGContext, width: CGFloat, height: CGFloat) {
        context.setFillColor(PanelStyle.imageCanvas.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func drawAspectFit(_ image: CGImage, in bounds: CGRect, context: CGContext) {
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
        context.draw(image, in: rect)
    }

    /// Quarter-turn rotation into a fresh bitmap. quarters = 1 means 90°
    /// clockwise, matching the viewport's layer transform.
    static func rotate(_ image: CGImage, quarters: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        let swapped = quarters % 2 == 1
        let outWidth = swapped ? height : width
        let outHeight = swapped ? width : height
        guard let context = CGContext(data: nil, width: outWidth, height: outHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        switch quarters {
        case 1: // 90° clockwise
            context.translateBy(x: 0, y: CGFloat(width))
            context.rotate(by: -.pi / 2)
        case 2: // 180°
            context.translateBy(x: CGFloat(width), y: CGFloat(height))
            context.rotate(by: .pi)
        case 3: // 90° counterclockwise
            context.translateBy(x: CGFloat(height), y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
