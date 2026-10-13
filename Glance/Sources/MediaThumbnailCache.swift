import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Small, downsampled previews for lists (Task Center rows, detail pane).
/// Decoding happens off the main thread and ImageIO produces the thumbnail
/// directly at the requested pixel size, so a 4000 px widget result never
/// gets fully decoded just to fill a 56 pt tile. Results are cached by path,
/// modification date and size, so scrolling back over a row is free.
final class MediaThumbnailCache {
    static let shared = MediaThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.glance.thumbnails", qos: .userInitiated, attributes: .concurrent)
    private let inFlightLock = NSLock()
    private var inFlight = Set<String>()

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// Already-decoded thumbnail, if any. Safe to call on the main thread.
    func cached(for url: URL, maxPixelSize: Int) -> NSImage? {
        guard let key = key(for: url, maxPixelSize: maxPixelSize) else { return nil }
        return cache.object(forKey: key as NSString)
    }

    /// Decodes in the background and calls `completion` on the main thread with
    /// the thumbnail, or nil when the file cannot be previewed. Callers must
    /// check that they still show the same item before applying the image.
    func load(_ url: URL, maxPixelSize: Int, completion: @escaping (NSImage?) -> Void) {
        guard url.isFileURL, let key = key(for: url, maxPixelSize: maxPixelSize) else {
            completion(nil); return
        }
        if let hit = cache.object(forKey: key as NSString) { completion(hit); return }
        queue.async { [weak self] in
            guard let self else { return }
            let image = Self.makeThumbnail(url: url, maxPixelSize: maxPixelSize)
            if let image {
                let cost = Int(image.size.width * image.size.height * 4)
                self.cache.setObject(image, forKey: key as NSString, cost: cost)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    private func key(for url: URL, maxPixelSize: Int) -> String? {
        guard url.isFileURL else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return "\(url.standardizedFileURL.path)|\(modified)|\(size)|\(maxPixelSize)"
    }

    private static func makeThumbnail(url: URL, maxPixelSize: Int) -> NSImage? {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
            return videoPoster(url: url, maxPixelSize: maxPixelSize)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func videoPoster(url: URL, maxPixelSize: Int) -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
