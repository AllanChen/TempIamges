import AppKit
import UniformTypeIdentifiers

/// Canvas view that accepts dragged media from anywhere — Finder file URLs,
/// browser/web URLs, file promises (WeChat, Photos, screenshot tools), and
/// raw image data. The owning window decides which extensions are droppable
/// (via `acceptsExtension`) and what to do with the result (via `onDrop`).
/// Shared by the image and video inspect windows.
final class MediaDropCanvasView: NSView {
    /// Kept in sync with PathDetector's media extension lists.
    static let imageExtensions = ImageFormatSupport.extensions
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mpg", "mpeg", "mpe", "m2v",
        "ts", "m2ts", "mts", "3gp", "3gpp", "3g2",
        "webm", "mkv", "avi"
    ]

    /// Return true when the dragged file extension is a kind this canvas accepts.
    var acceptsExtension: ((String) -> Bool)?
    /// Whether raw dragged image data (no URL at all) may be accepted.
    /// Image window only — the video canvas never wants a raw bitmap drop.
    var acceptsImageData = false
    /// Called with the resolved URL (local file, remote, or a temp file
    /// materialized from a promise/bitmap) and the drop location in this
    /// view's coordinate space.
    var onDrop: ((URL, NSPoint) -> Void)?

    private static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes
        .map { NSPasteboard.PasteboardType(rawValue: $0) }
    private static let imageDataTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType(rawValue: UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(rawValue: "public.heic"),
        NSPasteboard.PasteboardType(rawValue: "org.webmproject.webp"),
    ]
    static var imageDraggedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL] + imageDataTypes + promiseTypes
    }
    static var videoDraggedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL] + promiseTypes
    }
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.imageDraggedTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func accepts(_ url: URL) -> Bool {
        acceptsExtension?(url.pathExtension.lowercased()) == true
    }

    /// Local file URLs (Finder, other apps dragging real files).
    private func acceptedFileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return nil
        }
        return urls.first { accepts($0) }
    }

    /// Remote URLs (browser image/video drags carry public.url).
    private func acceptedRemoteURL(from pasteboard: NSPasteboard) -> URL? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return nil
        }
        return urls.first { !$0.isFileURL && accepts($0) }
    }

    /// File promises advertise only the promised content's UTIs — match by
    /// preferred filename extension.
    private func hasAcceptablePromise(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: Self.promiseTypes) != nil
    }

    private func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        if acceptedFileURL(from: pasteboard) != nil { return true }
        if acceptedRemoteURL(from: pasteboard) != nil { return true }
        if hasAcceptablePromise(pasteboard) { return true }
        if acceptsImageData,
           pasteboard.availableType(from: Self.imageDataTypes) != nil { return true }
        return false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptsDragging(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptsDragging(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        performDrop(sender)
    }

    func acceptsDragging(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender.draggingPasteboard)
    }

    func performDrop(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let point = convert(sender.draggingLocation, from: nil)
        let localURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let remoteURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.filter { !$0.isFileURL } ?? []
        let urls = localURLs + remoteURLs.filter { accepts($0) }
        if !urls.isEmpty {
            urls.forEach { onDrop?($0, point) }
            return true
        }
        if handlePromises(from: pasteboard, at: point) { return true }
        if acceptsImageData, handleImageData(from: pasteboard, at: point) { return true }
        return false
    }

    /// Receive promised files into a temp directory, then drop each one.
    private func handlePromises(from pasteboard: NSPasteboard, at point: NSPoint) -> Bool {
        guard let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
              !receivers.isEmpty else { return false }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var handled = false
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:],
                                          operationQueue: promiseQueue) { [weak self] fileURL, error in
                guard error == nil, let self, self.accepts(fileURL) else { return }
                DispatchQueue.main.async { self.onDrop?(fileURL, point) }
            }
            handled = true
        }
        return handled
    }

    /// Materialize raw dragged image data into a temp PNG, then drop it.
    private func handleImageData(from pasteboard: NSPasteboard, at point: NSPoint) -> Bool {
        guard let type = pasteboard.availableType(from: Self.imageDataTypes),
              let data = pasteboard.data(forType: type),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return false }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let url = destination.appendingPathComponent("dropped-\(UUID().uuidString.prefix(8)).png")
        guard (try? pngData.write(to: url)) != nil else { return false }
        onDrop?(url, point)
        return true
    }
}
