import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Writes a finished capture to disk. Captures are PNG (lossless, keeps alpha)
/// and land in ~/Pictures/Glance/<source name>-capture-<w>x<h>.png.
enum CaptureOutput {
    static func isCapture(_ url: URL) -> Bool {
        let folder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!.appendingPathComponent("Glance", isDirectory: true)
        return url.isFileURL && url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL && url.lastPathComponent.contains("-capture-")
    }

    static var directory: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Glance", isDirectory: true)
    }

    /// Saves `image` and returns its URL, or nil if the file could not be written.
    static func save(_ image: CGImage, sourceName: String?) -> URL? {
        let fm = FileManager.default
        do { try fm.createDirectory(at: directory, withIntermediateDirectories: true) } catch {
            Logger.info("Capture: cannot create \(directory.path): \(error.localizedDescription)")
            return nil
        }
        let base = sanitized(sourceName) ?? "Capture"
        let stem = "\(base)-capture-\(image.width)x\(image.height)"
        var url = directory.appendingPathComponent(stem).appendingPathExtension("png")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(stem)-\(n)").appendingPathExtension("png")
            n += 1
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    private static func sanitized(_ name: String?) -> String? {
        guard let name else { return nil }
        let stem = (name as NSString).deletingPathExtension
        let cleaned = stem.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(80))
    }
}
