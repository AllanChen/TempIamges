import AppKit
import AVFoundation

struct MediaInfo {
    let url: URL
    let isLocal: Bool
    let kind: Kind
    var dimensions: CGSize?
    var fileSize: Int64?       // bytes, only set for local
    var duration: TimeInterval? // seconds, only set for video

    enum Kind { case image, video }

    var filename: String { url.lastPathComponent }
    var formatName: String { (filename as NSString).pathExtension.uppercased() }
    var isVideo: Bool { kind == .video }

    static func from(_ path: DetectedPath) -> MediaInfo? {
        switch path {
        case .localImage(let url):  return MediaInfo(url: url, isLocal: true,  kind: .image)
        case .remoteImage(let url): return MediaInfo(url: url, isLocal: false, kind: .image)
        case .localVideo(let url):  return MediaInfo(url: url, isLocal: true,  kind: .video)
        case .remoteVideo(let url): return MediaInfo(url: url, isLocal: false, kind: .video)
        case .invalid: return nil
        }
    }
}

enum LoadedMedia {
    case image(NSImage, MediaInfo)
    case video(URL, naturalSize: CGSize, MediaInfo)

    var info: MediaInfo {
        switch self {
        case .image(_, let i): return i
        case .video(_, _, let i): return i
        }
    }

    var naturalSize: CGSize {
        switch self {
        case .image(let img, _): return img.size
        case .video(_, let size, _): return size
        }
    }
}

class ImageLoader {
    private let imageCache = NSCache<NSString, NSImage>()
    private let maxCacheSize: Int = 50 * 1024 * 1024 // 50MB

    init() {
        imageCache.totalCostLimit = maxCacheSize
    }

    /// Streams results back as each item finishes. `onProgress(i, nil)` means
    /// item `i` failed to load. `onComplete` fires once all items are done.
    func loadMedia(
        from paths: [DetectedPath],
        onProgress: @escaping (_ index: Int, _ loaded: LoadedMedia?) -> Void,
        onComplete: @escaping () -> Void
    ) {
        guard !paths.isEmpty else {
            onComplete()
            return
        }
        let group = DispatchGroup()

        for (i, path) in paths.enumerated() {
            guard var info = MediaInfo.from(path) else { continue }
            let url = info.url
            if info.isLocal {
                info.fileSize = fileSize(at: url.path)
            }

            group.enter()
            switch path {
            case .localImage, .remoteImage:
                loadImage(from: url) { image in
                    guard let img = image else {
                        DispatchQueue.main.async {
                            onProgress(i, nil); group.leave()
                        }
                        return
                    }
                    var i2 = info
                    i2.dimensions = img.size
                    DispatchQueue.main.async {
                        onProgress(i, .image(img, i2)); group.leave()
                    }
                }
            case .localVideo, .remoteVideo:
                probeVideo(url: url) { size, duration in
                    guard let s = size else {
                        DispatchQueue.main.async {
                            onProgress(i, nil); group.leave()
                        }
                        return
                    }
                    var i2 = info
                    i2.dimensions = s
                    i2.duration = duration
                    DispatchQueue.main.async {
                        onProgress(i, .video(url, naturalSize: s, i2)); group.leave()
                    }
                }
            case .invalid:
                group.leave()
            }
        }
        group.notify(queue: .main) { onComplete() }
    }

    private func fileSize(at path: String) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    private func probeVideo(url: URL, completion: @escaping (CGSize?, TimeInterval?) -> Void) {
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) {
            var error: NSError?
            guard asset.statusOfValue(forKey: "tracks", error: &error) == .loaded,
                  let track = asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            let raw = track.naturalSize.applying(track.preferredTransform)
            let size = CGSize(width: abs(raw.width), height: abs(raw.height))
            let dur = CMTimeGetSeconds(asset.duration)
            DispatchQueue.main.async {
                completion(size, dur.isFinite && dur > 0 ? dur : nil)
            }
        }
    }

    func loadImage(from url: URL, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = url.absoluteString as NSString

        if let cached = imageCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        if url.isFileURL {
            loadLocalImage(from: url, cacheKey: cacheKey, completion: completion)
        } else {
            loadRemoteImage(from: url, cacheKey: cacheKey, completion: completion)
        }
    }

    private func loadLocalImage(from url: URL, cacheKey: NSString, completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = NSImage(contentsOf: url) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let resized = self?.resizeImage(image, maxDimension: 800) ?? image
            let cost = Int(resized.size.width * resized.size.height * 4)
            self?.imageCache.setObject(resized, forKey: cacheKey, cost: cost)
            DispatchQueue.main.async { completion(resized) }
        }
    }

    private func loadRemoteImage(from url: URL, cacheKey: NSString, completion: @escaping (NSImage?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let image = NSImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let resized = self.resizeImage(image, maxDimension: 800)
            let cost = Int(resized.size.width * resized.size.height * 4)
            self.imageCache.setObject(resized, forKey: cacheKey, cost: cost)
            DispatchQueue.main.async { completion(resized) }
        }
        task.resume()
    }

    private func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let originalSize = image.size
        guard originalSize.width > maxDimension || originalSize.height > maxDimension else {
            return image
        }
        let ratio: CGFloat = originalSize.width > originalSize.height
            ? maxDimension / originalSize.width
            : maxDimension / originalSize.height
        let newSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    func clearCache() {
        imageCache.removeAllObjects()
        URLCache.shared.removeAllCachedResponses()
    }
}
