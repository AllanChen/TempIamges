import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Retains the encoded animation beside a normal poster image. A CALayer does
/// not advance NSImage's frames itself; each visible canvas owns its own player.
private var imageAnimationKey: UInt8 = 0
extension NSImage {
    var glanceAnimation: ImageAnimation? {
        get { objc_getAssociatedObject(self, &imageAnimationKey) as? ImageAnimation }
        set { objc_setAssociatedObject(self, &imageAnimationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

enum AnimatedImage {
    static func decode(data: Data) -> NSImage? {
        guard let animation = ImageAnimation(data: data),
              let poster = animation.frame(at: 0) else { return nil }
        let image = NSImage(cgImage: poster, size: NSSize(width: poster.width, height: poster.height))
        image.glanceAnimation = animation
        return image
    }
}

final class ImageAnimation {
    let data: Data
    let delays: [TimeInterval]
    /// nil means infinite. GIF stores repeats; APNG/WebP store total plays.
    let totalPlays: Int?
    private let source: CGImageSource
    private let lock = NSLock()
    var frameCount: Int { delays.count }

    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String? else { return nil }
        let dictionary: String
        let loopKey: String
        let delayKey: String
        let unclampedKey: String
        switch type {
        case "com.compuserve.gif":
            dictionary = kCGImagePropertyGIFDictionary as String
            loopKey = kCGImagePropertyGIFLoopCount as String
            delayKey = kCGImagePropertyGIFDelayTime as String
            unclampedKey = kCGImagePropertyGIFUnclampedDelayTime as String
        case "public.png":
            dictionary = kCGImagePropertyPNGDictionary as String
            loopKey = kCGImagePropertyAPNGLoopCount as String
            delayKey = kCGImagePropertyAPNGDelayTime as String
            unclampedKey = kCGImagePropertyAPNGUnclampedDelayTime as String
        case "org.webmproject.webp":
            dictionary = kCGImagePropertyWebPDictionary as String
            loopKey = kCGImagePropertyWebPLoopCount as String
            delayKey = kCGImagePropertyWebPDelayTime as String
            unclampedKey = kCGImagePropertyWebPUnclampedDelayTime as String
        default: return nil // Multi-page TIFF/HEIF documents are not animations.
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }
        let root = CGImageSourceCopyProperties(source, nil) as? [String: Any]
        let metadata = root?[dictionary] as? [String: Any] ?? [:]
        let loop = (metadata[loopKey] as? NSNumber)?.intValue
        if let loop {
            totalPlays = loop == 0 ? nil : (dictionary == "{GIF}" ? loop + 1 : loop)
        } else {
            totalPlays = 1
        }
        var delays: [TimeInterval] = []
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            let frame = properties?[dictionary] as? [String: Any] ?? [:]
            let raw = (frame[unclampedKey] as? NSNumber)?.doubleValue
                ?? (frame[delayKey] as? NSNumber)?.doubleValue ?? 0.1
            delays.append(raw.isFinite && raw >= 0.02 ? raw : 0.1)
        }
        self.data = data
        self.source = source
        self.delays = delays
    }

    /// ImageIO performs GIF disposal/compositing. Serialize access across
    /// compare panes and decode only the current frame, not an entire bitmap array.
    func frame(at index: Int) -> CGImage? {
        guard delays.indices.contains(index) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return CGImageSourceCreateImageAtIndex(source, index,
            [kCGImageSourceShouldCache: false,
             kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// One-shot frame scheduling, with decoding off the main thread. No timer is
/// retained while the canvas is hidden, detached, or its window is occluded.
final class ImageAnimationPlayer {
    private weak var view: NSView?
    private weak var layer: CALayer?
    private var animation: ImageAnimation?
    private var timer: Timer?
    private var generation = 0
    private var decoding = false
    private var index = 0
    private var plays = 0
    private var observers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "com.glance.animation", qos: .userInitiated)

    init(view: NSView, layer: CALayer) {
        self.view = view
        self.layer = layer
        for name in [NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                queue: .main) { [weak self] _ in self?.refreshVisibility() })
        }
    }

    deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func setImage(_ image: NSImage?) {
        stop()
        animation = image?.glanceAnimation
        index = 0
        plays = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
        refreshVisibility()
    }

    func stop() {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        decoding = false
        animation = nil
    }

    private var isVisible: Bool {
        guard let view, let window = view.window else { return false }
        return !view.isHiddenOrHasHiddenAncestor && window.isVisible &&
            window.occlusionState.contains(.visible)
    }

    func refreshVisibility() {
        guard isVisible else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil, !decoding, let animation,
              animation.totalPlays.map({ plays < $0 }) ?? true else { return }
        schedule(after: animation.delays[index])
    }

    private func schedule(after delay: TimeInterval) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.timer = nil
            self?.advance()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advance() {
        guard isVisible, let animation else { return }
        var next = index + 1
        if next == animation.frameCount {
            plays += 1
            if let limit = animation.totalPlays, plays >= limit { return }
            next = 0
        }
        let nextIndex = next
        let token = generation
        let started = ProcessInfo.processInfo.systemUptime
        decoding = true
        queue.async { [weak self] in
            let frame = animation.frame(at: nextIndex)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.decoding = false
                guard let frame else { self.stop(); return }
                self.index = nextIndex
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.layer?.contents = frame
                CATransaction.commit()
                if self.isVisible {
                    let elapsed = ProcessInfo.processInfo.systemUptime - started
                    self.schedule(after: max(0.001, animation.delays[nextIndex] - elapsed))
                }
            }
        }
    }
}

/// Preserve clipboard bytes instead of flattening GIF/APNG/WebP into PNG.
/// If the browser supplies only a still bitmap, no animation can be recovered.
enum ClipboardImageImport {
    static let types: [NSPasteboard.PasteboardType] = [
        .init(rawValue: UTType.gif.identifier),
        .init(rawValue: "org.webmproject.webp"), .png, .tiff,
        .init(rawValue: UTType.jpeg.identifier), .init(rawValue: "public.heic")
    ]

    static func materialize(from pasteboard: NSPasteboard) -> URL? {
        for type in types {
            guard let data = pasteboard.data(forType: type),
                  let url = materialize(data: data) else { continue }
            return url
        }
        return nil
    }

    static func materialize(data: Data) -> URL? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) as String?,
              let ext = UTType(type)?.preferredFilenameExtension else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GlanceClipboard", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("clipboard-\(UUID().uuidString).\(ext)")
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}
