import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import QuickLookThumbnailing

/// Persistent cache shared by remote images and videos. All filesystem and
/// download work stays off the main thread.
final class RemoteMediaDiskCache {
    static let shared = RemoteMediaDiskCache()

    private let queue = DispatchQueue(label: "com.glance.remote-media-cache", qos: .utility)
    private let directory: URL
    private let session: URLSession

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Glance/RemoteMedia", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    func cachedURL(for remoteURL: URL, completion: @escaping (URL?) -> Void) {
        queue.async {
            let url = self.cacheURL(for: remoteURL)
            let exists = FileManager.default.fileExists(atPath: url.path)
            DispatchQueue.main.async { completion(exists ? url : nil) }
        }
    }

    func store(_ data: Data, for remoteURL: URL, completion: ((URL?) -> Void)? = nil) {
        queue.async {
            do {
                try FileManager.default.createDirectory(at: self.directory,
                                                        withIntermediateDirectories: true)
                let target = self.cacheURL(for: remoteURL)
                try data.write(to: target, options: .atomic)
                completion?(target)
            } catch {
                Logger.warning("Remote cache write failed: \(error.localizedDescription)")
                completion?(nil)
            }
        }
    }

    func downloadIfNeeded(_ remoteURL: URL, completion: ((URL?) -> Void)? = nil) {
        cachedURL(for: remoteURL) { [weak self] cached in
            if let cached {
                completion?(cached)
                return
            }
            guard let self else { completion?(nil); return }
            // Stream large videos to a temporary file instead of holding the
            // entire response in memory.
            self.session.downloadTask(with: remoteURL) { temporaryURL, response, error in
                guard let temporaryURL, error == nil,
                      (response as? HTTPURLResponse).map({ $0.statusCode < 400 }) ?? true else {
                    DispatchQueue.main.async { completion?(nil) }
                    return
                }
                do {
                    try FileManager.default.createDirectory(at: self.directory,
                                                            withIntermediateDirectories: true)
                    let target = self.cacheURL(for: remoteURL)
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.moveItem(at: temporaryURL, to: target)
                    DispatchQueue.main.async { completion?(target) }
                } catch {
                    Logger.warning("Remote download cache failed: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion?(nil) }
                }
            }.resume()
        }
    }

    func clear() {
        queue.async { try? FileManager.default.removeItem(at: self.directory) }
    }

    private func cacheURL(for remoteURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let ext = Self.inferredExtension(for: remoteURL)
        return directory.appendingPathComponent(ext.isEmpty ? digest : "\(digest).\(ext)")
    }

    private static func inferredExtension(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty { return pathExtension }
        let query = url.query?.lowercased() ?? ""
        let patterns = [
            #"(?:^|[&/])(?:format|fm|ext)[=/]([a-z0-9]+)"#,
            #"(?:^|[&/])(?:format|fm|ext)=([a-z0-9]+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
                  let range = Range(match.range(at: 1), in: query) else { continue }
            return String(query[range])
        }
        return PathDetector.extensionFromBangSuffix(of: url.path)
    }
}

struct MediaInfo {
    let url: URL
    let isLocal: Bool
    let kind: Kind
    var dimensions: CGSize?
    var fileSize: Int64?       // bytes, only set for local
    var duration: TimeInterval? // seconds, only set for video
    /// Short human-readable hint about WHERE the file lives — used to
    /// disambiguate when multiple Spotlight matches share a filename.
    /// e.g. "~/Desktop/work". Rendered in the tile's metadata overlay.
    var disambiguationHint: String? = nil
    /// The raw search token (e.g. bare filename) that led to this tile.
    /// Used by the loading/failure UI so the user knows what is being
    /// searched for.
    var searchToken: String? = nil
    var sourceAppName: String? = nil

    enum Kind { case image, video, markdown, text, pdf, webPage, other, folder }

    var filename: String { url.lastPathComponent }
    var formatName: String { (filename as NSString).pathExtension.uppercased() }
    var isVideo: Bool    { kind == .video }
    var isMarkdown: Bool { kind == .markdown }
    var isText: Bool     { kind == .text }
    var isPDF: Bool      { kind == .pdf }
    var isWebPage: Bool  { kind == .webPage }
    var isOther: Bool    { kind == .other }
    var isFolder: Bool   { kind == .folder }
    /// True for kinds that have no inline preview — clicking the tile opens
    /// them in a separate viewer window instead.
    var opensInViewer: Bool {
        kind == .markdown || kind == .text || kind == .webPage || kind == .pdf
    }
    var hasIconContent: Bool {
        opensInViewer || kind == .other || kind == .folder
    }

    static func from(_ path: DetectedPath) -> MediaInfo? {
        switch path {
        case .localImage(let url):     return MediaInfo(url: url, isLocal: true,  kind: .image)
        case .remoteImage(let url):    return MediaInfo(url: url, isLocal: false, kind: .image)
        case .localVideo(let url):     return MediaInfo(url: url, isLocal: true,  kind: .video)
        case .remoteVideo(let url):    return MediaInfo(url: url, isLocal: false, kind: .video)
        case .localMarkdown(let url):  return MediaInfo(url: url, isLocal: true,  kind: .markdown)
        case .remoteMarkdown(let url): return MediaInfo(url: url, isLocal: false, kind: .markdown)
        case .localText(let url):      return MediaInfo(url: url, isLocal: true,  kind: .text)
        case .remoteText(let url):     return MediaInfo(url: url, isLocal: false, kind: .text)
        case .localPDF(let url):       return MediaInfo(url: url, isLocal: true,  kind: .pdf)
        case .remotePDF(let url):      return MediaInfo(url: url, isLocal: false, kind: .pdf)
        case .webPage(let url):        return MediaInfo(url: url, isLocal: false, kind: .webPage)
        case .localOther(let url):     return MediaInfo(url: url, isLocal: true,  kind: .other)
        case .remoteOther(let url):    return MediaInfo(url: url, isLocal: false, kind: .other)
        case .localFolder(let url):    return MediaInfo(url: url, isLocal: true,  kind: .folder)
        case .unresolvedFilename, .unresolvedRelativePath, .invalid: return nil
        }
    }
}

struct ImageTechnicalMetadata {
    var colorSpace: String?
    var bitDepth: Int?
    var hasAlpha: Bool?
}

enum LoadedMedia {
    case image(NSImage, MediaInfo)
    case video(URL, naturalSize: CGSize, MediaInfo)
    /// Markdown/webpage tiles don't load inline content; the placeholder is
    /// rendered in the tile, and clicking opens the viewer window.
    case openable(MediaInfo)

    var info: MediaInfo {
        switch self {
        case .image(_, let i): return i
        case .video(_, _, let i): return i
        case .openable(let i): return i
        }
    }

    var naturalSize: CGSize {
        switch self {
        case .image(let img, _): return img.size
        case .video(_, let size, _): return size
        case .openable: return CGSize(width: 320, height: 200)
        }
    }
}

class ImageLoader {
    private let imageCache = NSCache<NSString, NSImage>()
    private let originalImageCache = NSCache<NSString, NSImage>()
    private let maxCacheSize: Int = 50 * 1024 * 1024
    private let maxOriginalCacheSize: Int = 300 * 1024 * 1024
    private let loadSemaphore = DispatchSemaphore(value: 2)
    private let remoteLoadLock = NSLock()
    private var remoteLoads: [String: [(NSImage?) -> Void]] = [:]
    private lazy var remoteSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    init() {
        imageCache.totalCostLimit = maxCacheSize
        originalImageCache.totalCostLimit = maxOriginalCacheSize
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
            group.enter()
            let url = info.url
            let beginLoad: (MediaInfo) -> Void = { info in
            switch path {
            case .localImage, .remoteImage:
                self.loadImage(from: url) { image in
                    guard let img = image else {
                        DispatchQueue.main.async {
                            onProgress(i, nil); group.leave()
                        }
                        return
                    }
                    var i2 = info
                    i2.dimensions = self.originalImageCache.object(forKey: url.absoluteString as NSString)?.size ?? img.size
                    DispatchQueue.main.async {
                        onProgress(i, .image(img, i2)); group.leave()
                    }
                }
            case .localVideo, .remoteVideo:
                self.probeVideo(url: url) { size, duration in
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
            case .localMarkdown, .remoteMarkdown,
                 .localText, .remoteText,
                 .localPDF, .remotePDF,
                 .localOther, .remoteOther,
                 .localFolder,
                 .webPage:
                // No async work — the tile shows a placeholder icon and the
                // content is fetched only when the user clicks to open it
                // (or, for .other, when they reveal it in Finder).
                DispatchQueue.main.async {
                    onProgress(i, .openable(info)); group.leave()
                }
            case .unresolvedFilename, .unresolvedRelativePath, .invalid:
                // These should be filtered out by AppDelegate before reaching
                // the loader (unresolved cases go through FileNameResolver
                // first, and .invalid never has a usable URL).
                group.leave()
            }
            }
            if info.isLocal {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    info.fileSize = self?.fileSize(at: url.path)
                    beginLoad(info)
                }
            } else {
                beginLoad(info)
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
            loadRemoteCachedImage(from: url, cacheKey: cacheKey, fullResolution: false,
                                  completion: completion)
        }
    }

    /// Returns the original decoded image used to create Peek's thumbnail.
    /// A Peek-to-Inspect transition normally hits `originalImageCache`, so it
    /// does not fetch or decode the image a second time.
    func loadFullResolutionImage(from url: URL, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = url.absoluteString as NSString
        if let cached = originalImageCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        if url.isFileURL {
            decodeLocalImage(from: url, quickLookMaxDimension: 4096) { [weak self] image in
                guard let self, let image else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                self.cacheOriginal(image, key: cacheKey)
                DispatchQueue.main.async { completion(image) }
            }
        } else {
            loadRemoteCachedImage(from: url, cacheKey: cacheKey, fullResolution: true) { [weak self] image in
                guard let self = self, let image = image else {
                    completion(nil)
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let preview = self.resizeImage(image, maxDimension: 800)
                    self.imageCache.setObject(preview, forKey: cacheKey, cost: self.cost(of: preview))
                    DispatchQueue.main.async { completion(image) }
                }
            }
        }
    }

    func loadTechnicalMetadata(from url: URL,
                               completion: @escaping (ImageTechnicalMetadata) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var metadata = ImageTechnicalMetadata()
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                metadata.colorSpace = props[kCGImagePropertyColorModel] as? String
                metadata.bitDepth = props[kCGImagePropertyDepth] as? Int
                metadata.hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool
            }
            DispatchQueue.main.async { completion(metadata) }
        }
    }

    func loadFileSize(from url: URL, completion: @escaping (Int64?) -> Void) {
        guard url.isFileURL else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let size = self?.fileSize(at: url.path)
            DispatchQueue.main.async { completion(size) }
        }
    }

    private func loadLocalImage(from url: URL, cacheKey: NSString, completion: @escaping (NSImage?) -> Void) {
        decodeLocalImage(from: url, quickLookMaxDimension: 1600) { [weak self] image in
            guard let self, let image else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.cacheOriginal(image, key: cacheKey)
            let resized = self.resizeImage(image, maxDimension: 800)
            self.imageCache.setObject(resized, forKey: cacheKey, cost: self.cost(of: resized))
            DispatchQueue.main.async {
                completion(resized)
            }
        }
    }

    /// Decode with NSImage first (ImageIO plus native SVG support), then ask
    /// Quick Look for a bitmap representation. The fallback covers formats
    /// whose decoders live in macOS or an installed Quick Look extension,
    /// including many camera RAW and design formats.
    private func decodeLocalImage(from url: URL, quickLookMaxDimension: CGFloat,
                                  completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { completion(nil); return }
            self.loadSemaphore.wait()
            let image = NSImage(contentsOf: url)
            self.loadSemaphore.signal()
            if let image {
                completion(image)
                return
            }

            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: quickLookMaxDimension, height: quickLookMaxDimension),
                scale: 1,
                // Never accept the generic file icon as a successful image
                // preview when no decoder is available.
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
                if let error {
                    Logger.info("Quick Look image fallback failed for \(url.lastPathComponent): \(error.localizedDescription)")
                }
                completion(thumbnail?.nsImage)
            }
        }
    }

    private func loadRemoteImage(from url: URL, cacheKey: NSString, completion: @escaping (NSImage?) -> Void) {
        loadRemoteOriginal(from: url, cacheKey: cacheKey) { [weak self] image in
            guard let self = self, let image = image else {
                completion(nil)
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let resized = self.resizeImage(image, maxDimension: 800)
                self.imageCache.setObject(resized, forKey: cacheKey, cost: self.cost(of: resized))
                DispatchQueue.main.async { completion(resized) }
            }
        }
    }

    /// Prefer persistent cache. On first use, fetch from the network and show
    /// immediately; loadRemoteOriginal stores the bytes asynchronously for
    /// future sessions.
    private func loadRemoteCachedImage(from url: URL, cacheKey: NSString,
                                       fullResolution: Bool,
                                       completion: @escaping (NSImage?) -> Void) {
        RemoteMediaDiskCache.shared.cachedURL(for: url) { [weak self] cachedURL in
            guard let self else { completion(nil); return }
            if let cachedURL {
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let image = NSImage(contentsOf: cachedURL) else {
                        DispatchQueue.main.async {
                            fullResolution
                                ? self.loadRemoteOriginal(from: url, cacheKey: cacheKey, completion: completion)
                                : self.loadRemoteImage(from: url, cacheKey: cacheKey, completion: completion)
                        }
                        return
                    }
                    self.cacheOriginal(image, key: cacheKey)
                    let output = fullResolution ? image : self.resizeImage(image, maxDimension: 800)
                    if !fullResolution {
                        self.imageCache.setObject(output, forKey: cacheKey, cost: self.cost(of: output))
                    }
                    DispatchQueue.main.async { completion(output) }
                }
            } else if fullResolution {
                self.loadRemoteOriginal(from: url, cacheKey: cacheKey, completion: completion)
            } else {
                self.loadRemoteImage(from: url, cacheKey: cacheKey, completion: completion)
            }
        }
    }

    private func loadRemoteOriginal(from url: URL, cacheKey: NSString,
                                    completion: @escaping (NSImage?) -> Void) {
        if let cached = originalImageCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        let key = url.absoluteString
        remoteLoadLock.lock()
        if remoteLoads[key] != nil {
            remoteLoads[key]?.append(completion)
            remoteLoadLock.unlock()
            return
        }
        remoteLoads[key] = [completion]
        remoteLoadLock.unlock()

        func finish(_ image: NSImage?) {
            self.remoteLoadLock.lock()
            let callbacks = self.remoteLoads.removeValue(forKey: key) ?? []
            self.remoteLoadLock.unlock()
            DispatchQueue.main.async {
                callbacks.forEach { $0(image) }
            }
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let task = remoteSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                finish(nil)
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                finish(nil)
                return
            }
            guard data.count <= 50 * 1024 * 1024 else {
                finish(nil)
                return
            }
            guard let image = NSImage(data: data) else {
                // Some decoders are exposed through Quick Look rather than
                // NSImage. Materialize the response in the persistent cache
                // and let the same local fallback pipeline try it.
                RemoteMediaDiskCache.shared.store(data, for: url) { cachedURL in
                    guard let cachedURL else { finish(nil); return }
                    self.decodeLocalImage(from: cachedURL, quickLookMaxDimension: 4096) { image in
                        if let image { self.cacheOriginal(image, key: cacheKey) }
                        finish(image)
                    }
                }
                return
            }
            RemoteMediaDiskCache.shared.store(data, for: url)
            self.cacheOriginal(image, key: cacheKey)
            finish(image)
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

    private func cacheOriginal(_ image: NSImage, key: NSString) {
        originalImageCache.setObject(image, forKey: key, cost: cost(of: image))
    }

    private func cost(of image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }

    func clearCache() {
        imageCache.removeAllObjects()
        originalImageCache.removeAllObjects()
        URLCache.shared.removeAllCachedResponses()
        RemoteMediaDiskCache.shared.clear()
    }
}
