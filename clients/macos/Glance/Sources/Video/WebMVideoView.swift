import AppKit
import AVFoundation
import AVKit
import Network
import WebKit

/// Local WebM is converted into short HLS segments for native playback.
/// WebKit remains available for remote WebM and when ffmpeg is unavailable.
final class WebMVideoView: WKWebView {
    weak var dropTarget: MediaDropCanvasView?
    var onReady: ((Double, CGSize) -> Void)?
    var onTimeUpdate: ((Double) -> Void)?
    var onEnded: (() -> Void)?
    var onFailure: (() -> Void)?
    var onFrameReady: (() -> Void)?
    private(set) var videoTime = 0.0
    private(set) var videoDuration = 0.0
    private(set) var videoSize = CGSize.zero
    private(set) var isReady = false
    private var wantsPlay = false
    private var pendingSeek: (Double, (() -> Void)?)?
    private var seekCompletion: (() -> Void)?
    private var muted = false
    private var loadToken = UUID()
    private var wrapperDirectory: URL?
    private var sourceURL: URL
    private var usingFallback = false
    private var fallbackDirectory: URL?
    private var fallbackProcess: Process?
    private var streamingFallback: WebMStreamingFallback?
    private var streamingPlayer: AVPlayer?
    private var streamingLayer: AVPlayerLayer?
    private var streamingOverlay: PassthroughVideoOverlay?
    private var displayObservation: NSKeyValueObservation?
    private var streamingFirstFrameSent = false
    private var streamingTimeObserver: Any?
    private var streamingEndObserver: NSObjectProtocol?
    private var loadStartedAt = ProcessInfo.processInfo.systemUptime

    init(url: URL) {
        sourceURL = url
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let handler = WeakWebMMessageHandler()
        configuration.userContentController.add(handler, name: "glanceVideo")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.bridgeScript,
                                                                       injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: true))
        super.init(frame: .zero, configuration: configuration)
        handler.owner = self
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        if !startStreamingFallback() { loadSource(url) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        stopStreamingFallback()
        if fallbackProcess?.isRunning == true { fallbackProcess?.terminate() }
        if let wrapperDirectory { try? FileManager.default.removeItem(at: wrapperDirectory) }
        if let fallbackDirectory { try? FileManager.default.removeItem(at: fallbackDirectory) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        streamingOverlay?.frame = bounds
        streamingLayer?.frame = streamingOverlay?.bounds ?? .zero
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender) == true
    }

    private func releaseEmbeddedDragDestinations() {
        func visit(_ view: NSView) {
            for child in view.subviews {
                child.unregisterDraggedTypes()
                visit(child)
            }
        }
        visit(self)
    }

    private static let bridgeScript = """
        (() => {
          const video = document.querySelector('video');
          if (!video) return;
          const fit = () => {
            document.documentElement.style.cssText = 'margin:0;background:#000;overflow:hidden';
            document.body.style.cssText = 'margin:0;background:#000;overflow:hidden';
            video.style.setProperty('position', 'fixed', 'important');
            video.style.setProperty('inset', '0', 'important');
            video.style.setProperty('width', '100vw', 'important');
            video.style.setProperty('height', '100vh', 'important');
            video.style.setProperty('object-fit', 'contain', 'important');
            video.style.setProperty('background', '#000', 'important');
            video.controls = false;
          };
          fit();
          video.muted = false;
          video.pause();
          const send = (type, extra = {}) => window.webkit.messageHandlers.glanceVideo.postMessage({type, ...extra});
          video.addEventListener('loadedmetadata', () => { fit(); send('ready', {
            duration: video.duration, width: video.videoWidth, height: video.videoHeight
          }); });
          let frameSent = false;
          const firstFrame = () => {
            if (frameSent) return;
            frameSent = true;
            fit();
            send('frameReady');
          };
          let frameScheduled = false;
          const scheduleFirstFrame = () => {
            if (frameScheduled) return;
            frameScheduled = true;
            requestAnimationFrame(() => requestAnimationFrame(firstFrame));
          };
          video.addEventListener('loadeddata', scheduleFirstFrame);
          video.addEventListener('canplay', scheduleFirstFrame);
          window.addEventListener('resize', fit);
          video.addEventListener('timeupdate', () => send('time', {time: video.currentTime}));
          video.addEventListener('seeked', () => send('seeked', {time: video.currentTime}));
          video.addEventListener('ended', () => send('ended'));
          video.addEventListener('error', () => send('error', {
            code: video.error?.code ?? 0, message: video.error?.message ?? ''
          }));
          if (video.readyState >= 1) send('ready', {
            duration: video.duration, width: video.videoWidth, height: video.videoHeight
          });
          if (video.readyState >= 2) scheduleFirstFrame();
        })();
        """

    private func loadSource(_ url: URL) {
        isReady = false
        videoTime = 0
        loadToken = UUID()
        let token = loadToken
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceWebM-\(UUID().uuidString)", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let fileExtension = url.pathExtension.isEmpty ? "webm" : url.pathExtension.lowercased()
                let source = url.isFileURL ? "video.\(fileExtension)" : url.absoluteString
                if url.isFileURL {
                    let local = directory.appendingPathComponent(source)
                    do {
                        try FileManager.default.linkItem(at: url, to: local)
                    } catch {
                        // External volumes cannot be hard-linked into /tmp.
                        try FileManager.default.copyItem(at: url, to: local)
                    }
                }
                let encodedSource = String(data: try JSONEncoder().encode(source), encoding: .utf8) ?? "\"\""
                let html = """
                    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}
                    video{display:block;width:100vw;height:100vh;object-fit:contain;background:#000}</style></head>
                    <body><video playsinline preload="auto"></video>
                    <script>document.querySelector('video').src = \(encodedSource);</script></body></html>
                    """
                let page = directory.appendingPathComponent("index.html")
                try html.write(to: page, atomically: true, encoding: .utf8)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadToken == token else {
                        try? FileManager.default.removeItem(at: directory)
                        return
                    }
                    self.logLoadStage("source prepared")
                    if let previous = self.wrapperDirectory {
                        try? FileManager.default.removeItem(at: previous)
                    }
                    self.wrapperDirectory = directory
                    self.loadFileURL(page, allowingReadAccessTo: directory)
                }
            } catch {
                try? FileManager.default.removeItem(at: directory)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadToken == token else { return }
                    Logger.error("WebMVideoView: could not prepare \(Logger.redact(url.lastPathComponent)): \(error.localizedDescription)")
                    self.onFailure?()
                }
            }
        }
    }
    func replaceSource(with url: URL) {
        loadStartedAt = ProcessInfo.processInfo.systemUptime
        pendingSeek = (videoTime, nil)
        loadToken = UUID()
        stopStreamingFallback()
        if fallbackProcess?.isRunning == true { fallbackProcess?.terminate() }
        fallbackProcess = nil
        if let fallbackDirectory { try? FileManager.default.removeItem(at: fallbackDirectory) }
        fallbackDirectory = nil
        usingFallback = false
        sourceURL = url
        if !startStreamingFallback() { loadSource(url) }
    }
    static func ffmpegURL() -> URL? {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        let searchDirectories = pathEntries + [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin", "/usr/local/bin"
        ]
        return searchDirectories.lazy
            .map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static func generatePoster(from url: URL, completion: @escaping (NSImage?) -> Void) {
        generateFrame(from: url, at: 0, maxSize: NSSize(width: 1280, height: 720),
                      completion: completion)
    }
    static func generateThumbnail(from url: URL, completion: @escaping (NSImage?) -> Void) {
        generateFrame(from: url, at: 0.5, maxSize: NSSize(width: 320, height: 240),
                      completion: completion)
    }
    private static func generateFrame(from url: URL, at time: Double, maxSize: NSSize?,
                                      completion: @escaping (NSImage?) -> Void) {
        guard url.isFileURL, let ffmpeg = ffmpegURL() else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = ffmpeg
            var arguments = ["-nostdin", "-hide_banner", "-loglevel", "error",
                             "-i", url.path, "-ss", String(format: "%.3f", max(0, time)),
                             "-an", "-frames:v", "1"]
            if let maxSize {
                arguments += ["-vf", "scale=\(Int(maxSize.width)):\(Int(maxSize.height)):force_original_aspect_ratio=decrease"]
            }
            arguments += ["-f", "image2pipe", "-vcodec", maxSize == nil ? "png" : "mjpeg", "pipe:1"]
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let image: NSImage?
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                image = process.terminationStatus == 0 ? NSImage(data: data) : nil
            } catch {
                image = nil
            }
            DispatchQueue.main.async { completion(image) }
        }
    }
    private func logLoadStage(_ stage: String) {
        let elapsed = ProcessInfo.processInfo.systemUptime - loadStartedAt
        Logger.info("WebMVideoView: \(stage) after \(String(format: "%.2f", elapsed))s")
    }
    private func startStreamingFallback() -> Bool {
        guard !usingFallback, sourceURL.isFileURL,
              let ffmpeg = Self.ffmpegURL() else { return false }
        usingFallback = true
        isReady = false
        videoTime = 0
        videoDuration = 0
        videoSize = .zero
        let token = loadToken
        let streamer = WebMStreamingFallback(source: sourceURL, ffmpeg: ffmpeg)
        streamingFallback = streamer
        logLoadStage("streaming conversion started")
        Self.probeMetadata(from: sourceURL, ffmpeg: ffmpeg) { [weak self, weak streamer] duration, size in
            guard let self, let streamer, self.loadToken == token,
                  self.streamingFallback === streamer else { return }
            self.videoDuration = duration
            self.videoSize = size
            if self.isReady { self.onReady?(duration, size) }
        }
        streamer.start { [weak self, weak streamer] playlist in
            guard let self, let streamer, self.loadToken == token,
                  self.streamingFallback === streamer else { return }
            guard let playlist else {
                self.stopStreamingFallback()
                self.usingFallback = false
                if !self.transcodeUnsupportedWebM() { self.onFailure?() }
                return
            }
            self.logLoadStage("first stream segment ready")
            self.attachStreamingPlayer(url: playlist)
        }
        return true
    }
    private func attachStreamingPlayer(url: URL) {
        let player = AVPlayer(url: url)
        // Live HLS can briefly outrun ffmpeg's next segment. Keep the play
        // request pending and resume automatically when the buffer refills.
        player.automaticallyWaitsToMinimizeStalling = true
        player.isMuted = muted
        player.currentItem?.preferredForwardBufferDuration = 0.5
        let overlay = PassthroughVideoOverlay(frame: bounds)
        let videoLayer = AVPlayerLayer(player: player)
        videoLayer.frame = overlay.bounds
        videoLayer.videoGravity = .resizeAspect
        overlay.wantsLayer = true
        overlay.layer?.addSublayer(videoLayer)
        addSubview(overlay)
        streamingOverlay = overlay
        streamingLayer = videoLayer
        streamingPlayer = player
        displayObservation = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.streamingLayer === layer,
                      !self.streamingFirstFrameSent else { return }
                self.streamingFirstFrameSent = true
                self.logLoadStage("native first frame ready; play requested=\(self.wantsPlay); status=\(self.streamingPlayer?.timeControlStatus.rawValue ?? -1)")
                self.onFrameReady?()
                self.displayObservation = nil
            }
        }
        streamingTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            guard let self, time.seconds.isFinite else { return }
            self.videoTime = time.seconds
            self.onTimeUpdate?(time.seconds)
        }
        streamingEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            self?.wantsPlay = false
            self?.onEnded?()
        }
        isReady = true
        onReady?(videoDuration, videoSize)
        if let (time, completion) = pendingSeek {
            pendingSeek = nil
            seek(to: time, completion: completion)
        }
        Logger.info("WebMVideoView: native player attached; autoplay=\(wantsPlay)")
        if wantsPlay { player.play() }
    }
    private func stopStreamingFallback() {
        displayObservation = nil
        if let streamingTimeObserver, let streamingPlayer {
            streamingPlayer.removeTimeObserver(streamingTimeObserver)
        }
        streamingTimeObserver = nil
        if let streamingEndObserver { NotificationCenter.default.removeObserver(streamingEndObserver) }
        streamingEndObserver = nil
        streamingPlayer?.pause()
        streamingPlayer = nil
        streamingLayer?.player = nil
        streamingLayer = nil
        streamingFirstFrameSent = false
        streamingOverlay?.removeFromSuperview()
        streamingOverlay = nil
        streamingFallback?.stop()
        streamingFallback = nil
    }
    private static func probeMetadata(from url: URL, ffmpeg: URL,
                                      completion: @escaping (Double, CGSize) -> Void) {
        let candidates = [ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe"),
                          URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe"),
                          URL(fileURLWithPath: "/usr/local/bin/ffprobe")]
        guard let ffprobe = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            DispatchQueue.main.async { completion(0, .zero) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = ffprobe
            process.arguments = ["-v", "error", "-select_streams", "v:0",
                                 "-show_entries", "format=duration:stream=width,height",
                                 "-of", "json", url.path]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            var duration = 0.0
            var size = CGSize.zero
            if (try? process.run()) != nil {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    let format = info["format"] as? [String: Any]
                    duration = Double(format?["duration"] as? String ?? "") ?? 0
                    let stream = (info["streams"] as? [[String: Any]])?.first
                    size = CGSize(width: stream?["width"] as? Int ?? 0,
                                  height: stream?["height"] as? Int ?? 0)
                }
            }
            DispatchQueue.main.async { completion(duration, size) }
        }
    }
    private func transcodeUnsupportedWebM() -> Bool {
        guard !usingFallback, sourceURL.isFileURL,
              let ffmpeg = Self.ffmpegURL() else { return false }
        usingFallback = true
        isReady = false
        let token = loadToken
        let original = sourceURL
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceWebMFallback-\(UUID().uuidString)", isDirectory: true)
        let output = directory.appendingPathComponent("video.mp4")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-i", original.path,
            "-map", "0:v:0", "-map", "0:a?", "-sn",
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "23",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart", "-y", output.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: directory)
            Logger.error("WebMVideoView: fallback could not start: \(error.localizedDescription)")
            return false
        }
        fallbackProcess = process
        logLoadStage("unsupported media; conversion started")
        Logger.info("WebMVideoView: converting unsupported WebM \(Logger.redact(original.lastPathComponent))")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            process.waitUntilExit()
            DispatchQueue.main.async {
                guard let self, self.loadToken == token else {
                    try? FileManager.default.removeItem(at: directory)
                    return
                }
                self.fallbackProcess = nil
                self.logLoadStage("conversion finished")
                guard process.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: output.path) else {
                    try? FileManager.default.removeItem(at: directory)
                    Logger.error("WebMVideoView: fallback conversion failed (exit \(process.terminationStatus))")
                    self.onFailure?()
                    return
                }
                self.fallbackDirectory = directory
                self.loadSource(output)
            }
        }
        return true
    }
    func playVideo() {
        wantsPlay = true
        if let streamingPlayer {
            streamingPlayer.play()
            return
        }
        guard isReady else { return }
        evaluateJavaScript("document.querySelector('video')?.play().catch(() => {})")
    }
    func pauseVideo() {
        wantsPlay = false
        if let streamingPlayer {
            streamingPlayer.pause()
            return
        }
        evaluateJavaScript("document.querySelector('video')?.pause()")
    }
    func seek(to seconds: Double, completion: (() -> Void)? = nil) {
        if let streamingPlayer {
            let target = max(0, seconds.isFinite ? seconds : 0)
            streamingPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                                 toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                DispatchQueue.main.async { completion?() }
            }
            return
        }
        guard isReady else {
            pendingSeek = (seconds, completion)
            return
        }
        seekCompletion = completion
        let target = max(0, seconds.isFinite ? seconds : 0)
        evaluateJavaScript("(() => { const v = document.querySelector('video'); if (!v) return; if (Math.abs(v.currentTime - \(target)) < 0.01 && !v.seeking) { window.webkit.messageHandlers.glanceVideo.postMessage({type:'seeked',time:v.currentTime}); } else { v.currentTime = \(target); } })()") { [weak self] _, error in
            if error != nil {
                let completion = self?.seekCompletion
                self?.seekCompletion = nil
                completion?()
            }
        }
    }
    func setVideoMuted(_ value: Bool) {
        muted = value
        if let streamingPlayer {
            streamingPlayer.isMuted = value
            return
        }
        evaluateJavaScript("document.querySelector('video').muted = \(value ? "true" : "false")")
    }
    var isVideoMuted: Bool { muted }
    func captureThumbnail(_ completion: @escaping (NSImage?) -> Void) {
        if streamingPlayer != nil {
            Self.generatePoster(from: sourceURL, completion: completion)
        } else {
            takeSnapshot(with: nil) { image, _ in completion(image) }
        }
    }
    func captureFrame(_ completion: @escaping (NSImage?) -> Void) {
        if streamingPlayer != nil {
            Self.generateFrame(from: sourceURL, at: videoTime, maxSize: nil, completion: completion)
            return
        }
        let script = """
            (() => { const v = document.querySelector('video');
              if (!v || !v.videoWidth || !v.videoHeight) return null;
              const c = document.createElement('canvas');
              c.width = v.videoWidth; c.height = v.videoHeight;
              c.getContext('2d').drawImage(v, 0, 0);
              return c.toDataURL('image/png'); })()
            """
        evaluateJavaScript(script) { [weak self] result, _ in
            guard let dataURL = result as? String else {
                self?.takeSnapshot(with: nil) { image, _ in completion(image) }
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let encoded = String(dataURL.split(separator: ",", maxSplits: 1).last ?? "")
                let image = Data(base64Encoded: encoded).flatMap(NSImage.init(data:))
                DispatchQueue.main.async {
                    if let image {
                        completion(image)
                    } else {
                        self?.takeSnapshot(with: nil) { image, _ in completion(image) }
                    }
                }
            }
        }
    }
    func receive(_ message: WKScriptMessage) {
        guard streamingFallback == nil else { return }
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            logLoadStage("metadata ready")
            releaseEmbeddedDragDestinations()
            isReady = true
            videoDuration = body["duration"] as? Double ?? 0
            videoSize = CGSize(width: body["width"] as? Double ?? 0,
                               height: body["height"] as? Double ?? 0)
            // onReady may immediately start playback, so restore audio first.
            setVideoMuted(muted)
            onReady?(videoDuration, videoSize)
            if let (time, completion) = pendingSeek {
                pendingSeek = nil
                seek(to: time, completion: completion)
            }
            if wantsPlay { playVideo() }
        case "time":
            videoTime = body["time"] as? Double ?? videoTime
            onTimeUpdate?(videoTime)
        case "seeked":
            videoTime = body["time"] as? Double ?? videoTime
            let completion = seekCompletion
            seekCompletion = nil
            completion?()
        case "ended":
            wantsPlay = false
            onEnded?()
        case "frameReady":
            logLoadStage("first frame ready")
            releaseEmbeddedDragDestinations()
            if !wantsPlay { pauseVideo() }
            onFrameReady?()
        case "error":
            Logger.warning("WebMVideoView: media element failed (code \(body["code"] ?? 0)); \(body["message"] ?? "")")
            if !startStreamingFallback() { onFailure?() }
        default: break
        }
    }
}

final class WeakWebMMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: WebMVideoView?
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}
