import AppKit
import AVFoundation
import AVKit
import Network
import WebKit

final class VideoInspectViewport: NSView {
    let index: Int
    let player: AVPlayer?
    private let playerView: AVPlayerView?
    private let webMView: WebMVideoView?
    private let webMPoster = PassthroughVideoPosterView()
    private var posterRequestToken = UUID()
    private var awaitingWebMFrame = false
    private let muteButton = InspectToolbarButton(symbol: "speaker.wave.2.fill", tooltip: "Mute".localized)
    private let compareDimmer = CALayer()
    private let loadingView = FocusSweepLoadingView(frame: .zero)
    private let failureView = LoadFailedAnimationView(frame: .zero)
    private let widgetProcessingBorder = VideoNonHitTestingView()
    private let widgetProcessingIndicator = VideoNonHitTestingView()
    private let widgetProcessingDot = PanelStyle.makeStatusDot(color: PanelStyle.success)
    private var widgetIndicatorCenterY: CGFloat?
    private var statusObservation: NSKeyValueObservation?
    var onActivate: (() -> Void)?
    var onReady: (() -> Void)?
    var onWebMMetadata: ((Double, CGSize) -> Void)?
    var onWebMFrameReady: (() -> Void)?
    var onWebMPosterReady: ((NSImage) -> Void)?
    var onTimeUpdate: ((Double) -> Void)?
    var onEnded: (() -> Void)?
    var videoSize: CGSize { webMView?.videoSize ?? player?.currentItem?.presentationSize ?? .zero }
    var currentTime: Double { webMView?.videoTime ?? player?.currentTime().seconds ?? 0 }
    var hasReachedEnd: Bool {
        let duration = webMView?.videoDuration ?? player?.currentItem?.duration.seconds ?? 0
        let time = currentTime
        // Also recognize a manual seek to the end, which may not emit an end
        // notification. Use each video's duration, not another filmstrip item's.
        return duration.isFinite && duration > 0 && time.isFinite && time >= duration
    }
    weak var dropTarget: MediaDropCanvasView? {
        didSet {
            webMView?.dropTarget = dropTarget
            (playerView as? PassthroughVideoPlayerView)?.dropTarget = dropTarget
        }
    }
    init(index: Int, url: URL) {
        self.index = index
        if url.pathExtension.lowercased() == "webm" {
            player = nil
            playerView = nil
            webMView = WebMVideoView(url: url)
        } else {
            let nativePlayer = AVPlayer(url: url)
            nativePlayer.isMuted = false
            nativePlayer.automaticallyWaitsToMinimizeStalling = false
            player = nativePlayer
            let nativeView = PassthroughVideoPlayerView(frame: .zero)
            // This surface delegates all interaction to Video Inspect. AVKit's
            // default paused-frame analysis still creates a VisionKit overlay
            // even with controlsStyle == .none and hit testing disabled. Its
            // VKCActionInfoView constraints conflicted during live resize in
            // the 2026-09-27 crash log. Disable it before attaching the player.
            if #available(macOS 13.0, *) {
                nativeView.allowsVideoFrameAnalysis = false
            }
            nativeView.controlsStyle = .none
            nativeView.videoGravity = .resizeAspect
            nativeView.player = nativePlayer
            nativeView.registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
            playerView = nativeView
            webMView = nil
        }
        super.init(frame: .zero)
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        layer?.backgroundColor = PanelStyle.inspectCanvas.cgColor
        if let playerView {
            playerView.wantsLayer = true
            playerView.layer?.cornerRadius = 5
            playerView.layer?.masksToBounds = true
            addSubview(playerView)
        }
        if let webMView {
            webMView.layer?.cornerRadius = 5
            webMView.layer?.masksToBounds = true
            webMView.onReady = { [weak self] duration, size in
                guard let self else { return }
                self.failureView.isHidden = true
                self.onWebMMetadata?(duration, size)
                self.onReady?()
            }
            webMView.onTimeUpdate = { [weak self] time in self?.onTimeUpdate?(time) }
            webMView.onEnded = { [weak self] in self?.onEnded?() }
            webMView.onFrameReady = { [weak self] in
                guard let self else { return }
                self.awaitingWebMFrame = false
                self.posterRequestToken = UUID()
                self.webMPoster.isHidden = true
                self.webMPoster.image = nil
                self.loadingView.setLoading(false)
                self.onWebMFrameReady?()
            }
            webMView.onFailure = { [weak self] in
                guard let self else { return }
                self.awaitingWebMFrame = false
                self.webMPoster.isHidden = true
                self.webMPoster.image = nil
                self.loadingView.setLoading(false)
                self.failureView.isHidden = false
            }
            addSubview(webMView)
            webMPoster.imageScaling = .scaleProportionallyUpOrDown
            webMPoster.isHidden = true
            addSubview(webMPoster)
            prepareWebMPoster(from: url)
        }
        addSubview(loadingView)
        addSubview(failureView)
        failureView.isHidden = true
        compareDimmer.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
        compareDimmer.opacity = 0
        layer?.addSublayer(compareDimmer)
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        muteButton.updateTooltip("Mute".localized)
        muteButton.isHidden = true
        addSubview(muteButton)
        widgetProcessingBorder.wantsLayer = true
        widgetProcessingBorder.layer?.borderWidth = 2
        widgetProcessingBorder.layer?.borderColor = PanelStyle.accent.withAlphaComponent(0.8).cgColor
        widgetProcessingBorder.layer?.cornerRadius = 12
        widgetProcessingBorder.layer?.shadowColor = PanelStyle.accent.cgColor
        widgetProcessingBorder.layer?.shadowOpacity = 0.28
        widgetProcessingBorder.layer?.shadowOffset = .zero
        widgetProcessingBorder.layer?.shadowRadius = 16
        widgetProcessingBorder.isHidden = true
        addSubview(widgetProcessingBorder, positioned: .above, relativeTo: nil)
        widgetProcessingDot.wantsLayer = true
        widgetProcessingDot.layer?.cornerRadius = 8
        widgetProcessingDot.layer?.shadowColor = PanelStyle.success.cgColor
        widgetProcessingDot.layer?.shadowOpacity = 0.85
        widgetProcessingDot.layer?.shadowOffset = .zero
        widgetProcessingDot.layer?.shadowRadius = 10
        widgetProcessingIndicator.addSubview(widgetProcessingDot)
        widgetProcessingIndicator.setAccessibilityElement(true)
        widgetProcessingIndicator.setAccessibilityLabel("Task running".localized)
        widgetProcessingIndicator.isHidden = true
        addSubview(widgetProcessingIndicator, positioned: .above, relativeTo: nil)
        if player != nil { observePlayerItem() }
        else { loadingView.setLoading(true) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        playerView?.frame = bounds
        webMView?.frame = bounds
        webMPoster.frame = bounds
        compareDimmer.frame = bounds
        muteButton.frame = NSRect(x: bounds.maxX - 40, y: bounds.maxY - 40,
                                  width: 32, height: 32)
        let loader = FocusSweepLoadingView.preferredSize
        loadingView.frame = NSRect(x: bounds.midX - loader.width / 2,
                                   y: bounds.midY - loader.height / 2,
                                   width: loader.width, height: loader.height)
        let failed = LoadFailedAnimationView.preferredSize
        failureView.frame = NSRect(x: bounds.midX - failed.width / 2,
                                   y: bounds.midY - failed.height / 2,
                                   width: failed.width, height: failed.height)
        widgetProcessingBorder.frame = bounds.insetBy(dx: 2, dy: 2)
        widgetProcessingIndicator.frame = NSRect(x: max(0, bounds.maxX - 48),
                                                  y: max(0, (widgetIndicatorCenterY ?? bounds.maxY - 30) - 18),
                                                  width: 36, height: 36)
        widgetProcessingDot.frame = NSRect(x: 10, y: 10, width: 16, height: 16)
    }
    func setWidgetIndicatorCenterY(_ centerY: CGFloat?) {
        guard widgetIndicatorCenterY != centerY else { return }
        widgetIndicatorCenterY = centerY
        needsLayout = true
    }
    func setWidgetProcessing(_ processing: Bool) {
        widgetProcessingBorder.isHidden = !processing
        widgetProcessingIndicator.isHidden = !processing
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let layer = widgetProcessingBorder.layer {
            if processing && !reduceMotion && layer.animation(forKey: "widgetMainBreathing") == nil {
                let animation = CABasicAnimation(keyPath: "borderColor")
                animation.fromValue = PanelStyle.accent.withAlphaComponent(0.35).cgColor
                animation.toValue = PanelStyle.accent.withAlphaComponent(0.8).cgColor
                animation.duration = 0.75
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: "widgetMainBreathing")
            } else if !processing || reduceMotion {
                layer.removeAnimation(forKey: "widgetMainBreathing")
            }
        }
        if let layer = widgetProcessingDot.layer {
            if processing && !reduceMotion && layer.animation(forKey: "widgetRunningDotBreathing") == nil {
                let glow = CABasicAnimation(keyPath: "shadowOpacity")
                glow.fromValue = 0.3
                glow.toValue = 1.0
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0.55
                fade.toValue = 1.0
                let animation = CAAnimationGroup()
                animation.animations = [glow, fade]
                animation.duration = 0.9
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: "widgetRunningDotBreathing")
            } else if !processing || reduceMotion {
                layer.removeAnimation(forKey: "widgetRunningDotBreathing")
            }
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropTarget?.acceptsDragging(sender) == true ? .copy : [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropTarget?.acceptsDragging(sender) == true ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { dropTarget?.performDrop(sender) == true }
    func replaceSource(with url: URL) {
        if let webMView {
            failureView.isHidden = true
            loadingView.setLoading(true)
            prepareWebMPoster(from: url)
            webMView.replaceSource(with: url)
            return
        }
        guard let player else { return }
        let time = player.currentTime()
        let wasPlaying = player.rate != 0
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        observePlayerItem()
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            if wasPlaying { self?.player?.playImmediately(atRate: 1) }
        }
    }
    private func prepareWebMPoster(from url: URL) {
        posterRequestToken = UUID()
        let token = posterRequestToken
        let startedAt = ProcessInfo.processInfo.systemUptime
        awaitingWebMFrame = true
        webMPoster.image = nil
        webMPoster.isHidden = true
        WebMVideoView.generatePoster(from: url) { [weak self] image in
            guard let self, self.posterRequestToken == token,
                  self.awaitingWebMFrame, let image else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            Logger.info("WebMVideoView: poster ready after \(String(format: "%.2f", elapsed))s")
            self.webMPoster.image = image
            self.webMPoster.isHidden = false
            self.onWebMPosterReady?(image)
        }
    }
    func captureWebMThumbnail(_ completion: @escaping (NSImage?) -> Void) {
        webMView?.captureThumbnail(completion)
    }
    private func observePlayerItem() {
        guard let player else { return }
        statusObservation = nil
        failureView.isHidden = true
        loadingView.setLoading(true)
        statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.loadingView.setLoading(false)
                    self.failureView.isHidden = true
                    self.onReady?()
                case .failed:
                    self.loadingView.setLoading(false)
                    self.failureView.isHidden = false
                case .unknown:
                    self.failureView.isHidden = true
                    self.loadingView.setLoading(true)
                @unknown default:
                    self.loadingView.setLoading(false)
                    self.failureView.isHidden = false
                }
            }
        }
    }
    func setCompareDimmed(_ dimmed: Bool) { compareDimmer.opacity = dimmed ? 1 : 0 }
    var isMuted: Bool { webMView?.isVideoMuted ?? player?.isMuted ?? true }
    func setMuted(_ muted: Bool) {
        if let webMView { webMView.setVideoMuted(muted) }
        else { player?.isMuted = muted }
        updateMuteButton()
    }
    var onActionMenu: ((NSEvent) -> Void)?
    @objc private func toggleMute() { setMuted(!isMuted) }
    private func updateMuteButton() { muteButton.setSymbol(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"); muteButton.updateTooltip((isMuted ? "Unmute" : "Mute").localized); muteButton.isActive = !isMuted }
    func play() { if let webMView { webMView.playVideo() } else { player?.playImmediately(atRate: 1) } }
    func pause() { if let webMView { webMView.pauseVideo() } else { player?.pause() } }
    func seek(to time: Double, completion: @escaping () -> Void) {
        if let webMView { webMView.seek(to: time, completion: completion) }
        else if let player {
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { _ in completion() }
        } else { completion() }
    }
    func captureFrame(at time: Double, completion: @escaping (NSImage?) -> Void) {
        if let webMView { webMView.captureFrame(completion); return }
        guard let asset = player?.currentItem?.asset else { completion(nil); return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let target = CMTime(seconds: max(0, time), preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: target)]) { [generator] _, cgImage, _, _, _ in
            let image = cgImage.map { cgImage in
                NSImage(cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            DispatchQueue.main.async { completion(image) }
        }
    }
    override func mouseDown(with event: NSEvent) {
        // Double-click toggles between aspect-fit and a 2× zoom, mirroring the
        // image viewer's double-click-to-zoom gesture.
        if event.clickCount == 2 {
            zoomScale = zoomScale > 1.01 ? 1 : 2
            applyZoom()
            return
        }
        onActivate?(); super.mouseDown(with: event)
    }
    private var zoomScale: CGFloat = 1
    func fitToView() {
        zoomScale = 1
        playerView?.videoGravity = .resizeAspect
        applyZoom()
    }
    private func applyZoom() {
        let transform = zoomScale > 1.01
            ? CGAffineTransform(scaleX: zoomScale, y: zoomScale)
            : CGAffineTransform.identity
        playerView?.layer?.setAffineTransform(transform)
        webMView?.layer?.setAffineTransform(transform)
    }
    override func rightMouseDown(with event: NSEvent) {
        if let onActionMenu { onActionMenu(event) } else { super.rightMouseDown(with: event) }
    }
}
final class PassthroughVideoPosterView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class PassthroughVideoPlayerView: AVPlayerView {
    weak var dropTarget: MediaDropCanvasView?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender) == true
    }
}

final class PassthroughVideoOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
