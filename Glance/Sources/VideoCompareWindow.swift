import AppKit
import AVFoundation
import AVKit
import WebKit

/// Technical details of one video, loaded asynchronously from the asset's
/// tracks. Every field is optional — a missing track simply leaves it nil.
struct VideoTechnicalMetadata {
    var fps: Float?
    var videoCodec: String?
    var audioCodec: String?
    /// Estimated data rate of the video track, in bits per second.
    var videoBitrate: Float?
}

/// Video Inspect mirrors ImageInspectWindow's Focus and Compare states. AVKit's
/// system controls are hidden; all controls below use Glance's darkroom theme.
final class VideoCompareWindow: NSWindow, NSWindowDelegate {
    private enum Mode { case focus, compare }
    private var infos: [MediaInfo]
    private var mode: Mode = .focus
    private var focusedIndex = 0
    private var compareIndices: (Int, Int)?
    private var activeCompareSlot = 1
    private var viewports: [VideoInspectViewport] = []
    private var durations: [Double]
    private var videoMetadata: [VideoTechnicalMetadata?]
    private let pathDetector = PathDetector()
    private var currentTime = 0.0
    private var isPlaying = false
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var generation = UUID()
    private var fittedVideoSignature = ""

    private static let designSize = NSSize(width: 1554, height: 1012)
    private let canvas = MediaDropCanvasView()
    private let inspectToolbar = NSView()
    private let identityBar = VideoTitlebar()
    private let closeTrafficButton = NSButton()
    private let minimizeTrafficButton = NSButton()
    private let zoomTrafficButton = NSButton()
    private let focusButton = InspectToolbarButton(symbol: "photo", tooltip: "Focus".localized)
    private let compareButton = InspectToolbarButton(symbol: "rectangle.split.2x1", tooltip: "Compare".localized)
    private let revealButton = InspectToolbarButton(symbol: "folder", tooltip: "Reveal in Finder".localized)
    private let moreButton = InspectToolbarButton(symbol: "ellipsis", tooltip: "More".localized)
    private let captureButton = InspectToolbarButton(symbol: "camera", tooltip: "Capture frame".localized)
    private let replayButton = InspectToolbarButton(symbol: "arrow.counterclockwise", tooltip: "Replay".localized)
    private let pinButton = InspectToolbarButton(symbol: "pin", tooltip: "Pin on Top".localized)
    private let widgetMarketButton = InspectToolbarButton(symbol: "square.grid.2x2", tooltip: "Widget Market".localized)
    private var isPinned = false
    private let playbackBar = VideoPlaybackBar()
    private let captureFeedback = CaptureFeedbackView()
    private let captureThumbnail = CaptureThumbnailButton()
    private var pendingCaptureURL: URL?
    private var captureThumbnailTimer: Timer?
    private var captureThumbnailGeneration = UUID()
    private var frameCaptureGeneration = UUID()
    private var shouldResumeAfterCapture = false
    private let infoPanel = VideoInformationView()
    private var infoVisible = false
    private let playButton = InspectToolbarButton(symbol: "play.fill", tooltip: "Play".localized)
    private let timeline = WarmVideoTimeline()
    private let currentLabel = NSTextField(labelWithString: "0:00")
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let filmstrip = VideoFilmstripView()
    /// Fired with the temp-file URL of a captured frame; AppDelegate routes it
    /// into the image inspect window.
    var onCaptureFrame: ((URL) -> Void)?
    /// Themed right-click menu (mute controls), rebuilt per presentation.
    private var actionsPanel: ActionMenuPanel?

    init?(infos: [MediaInfo], focusedIndex: Int = 0, startsInCompare: Bool = false) {
        let videos = infos.filter { $0.kind == .video }
        guard !videos.isEmpty else { return nil }
        self.infos = videos
        self.focusedIndex = min(max(0, focusedIndex), max(0, videos.count - 1))
        self.durations = Array(repeating: 0, count: videos.count)
        self.videoMetadata = Array(repeating: nil, count: videos.count)
        super.init(contentRect: Self.initialFrame(),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        title = "Video Inspect".localized
        titleVisibility = .hidden; titlebarAppearsTransparent = true
        appearance = NSAppearance(named: .darkAqua); backgroundColor = PanelStyle.inspectBackground
        minSize = NSSize(width: 320, height: 180)
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true; delegate = self
        registerForDraggedTypes(MediaDropCanvasView.videoDraggedTypes)
        compareIndices = videos.count > 1 ? (0, 1) : nil
        mode = startsInCompare && videos.count > 1 ? .compare : .focus
        buildUI()
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    private static func initialFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        guard let screen = ScreenManager.shared.screenForMouseLocation(mouse) ?? NSScreen.main else {
            return NSRect(origin: mouse, size: designSize)
        }
        let visible = screen.visibleFrame
        let scale = min(1, visible.width / designSize.width, visible.height / designSize.height)
        return ScreenManager.shared.centerFrame(
            for: NSSize(width: designSize.width * scale, height: designSize.height * scale), on: screen
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        // AppKit calls setFrame repeatedly while it is in its live-resize
        // display cycle. Do not synchronously mutate the content hierarchy
        // from here; that can re-enter AppKit's layout pass and raise an
        // internal NSWindow layout exception.
        super.setFrame(frameRect, display: flag)
    }
    func windowDidResize(_ notification: Notification) {
        layoutContent()
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        layoutContent()
    }
    override func sendEvent(_ event: NSEvent) {
        // Space is a regular keyDown, not a reliable key equivalent. Handle
        // it at the window boundary so AVPlayerView/other responders cannot
        // consume it before synchronized playback toggles.
        if event.type == .keyDown,
           event.keyCode == 49,
           !event.isARepeat,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            isPlaying ? pausePlayback() : playPlayback()
            return
        }
        // The floating playback controls stay available while the video plays.
        super.sendEvent(event)
    }
    @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canvas.acceptsDragging(sender) ? .copy : []
    }
    @objc func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }
    @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canvas.performDrop(sender)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           pasteRemoteVideoFromClipboard() {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if mode == .compare {
            focusTapped()
        } else {
            close()
        }
    }

    private func buildUI() {
        // Keep the registered drop target at the root of the window so AVKit's
        // layered player surfaces cannot prevent drag-destination discovery.
        contentView = canvas
        let root = canvas
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectBackground)
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(NSColor.white.withAlphaComponent(0.22))
        root.layer?.masksToBounds = true
        canvas.acceptsExtension = { ext in
            MediaDropCanvasView.videoExtensions.contains(ext)
        }
        canvas.onDrop = { [weak self] url, point in
            self?.handleDroppedVideo(url: url, at: point)
        }
        configureTraffic(closeTrafficButton, color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), tooltip: "Close".localized, action: #selector(closeTapped))
        configureTraffic(minimizeTrafficButton, color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), tooltip: "Minimize".localized, action: #selector(minimizeTapped))
        configureTraffic(zoomTrafficButton, color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), tooltip: "Zoom".localized, action: #selector(zoomTapped))
        [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].forEach(identityBar.addSubview)
        canvas.addSubview(identityBar)
        focusButton.target = self; focusButton.action = #selector(focusTapped)
        compareButton.target = self; compareButton.action = #selector(compareTapped)
        revealButton.target = self; revealButton.action = #selector(revealTapped)
        moreButton.target = self; moreButton.action = #selector(moreTapped)
        captureButton.target = self; captureButton.action = #selector(captureTapped)
        replayButton.target = self; replayButton.action = #selector(replayTapped)
        pinButton.target = self; pinButton.action = #selector(pinTapped)
        widgetMarketButton.target = self; widgetMarketButton.action = #selector(widgetMarketTapped)
        pinButton.isActive = isPinned
        inspectToolbar.wantsLayer = true
        inspectToolbar.layer?.backgroundColor = NSColor(
            srgbRed: 22 / 255, green: 23 / 255, blue: 25 / 255, alpha: 0.90
        ).cgColor
        inspectToolbar.layer?.borderWidth = 1
        inspectToolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        inspectToolbar.layer?.cornerRadius = 15
        inspectToolbar.layer?.shadowColor = NSColor(
            srgbRed: 20 / 255, green: 23 / 255, blue: 26 / 255, alpha: 0.24
        ).cgColor
        inspectToolbar.layer?.shadowOpacity = 1
        inspectToolbar.layer?.shadowOffset = CGSize(width: 0, height: -8)
        inspectToolbar.layer?.shadowRadius = 12
        for button in [captureButton, focusButton, compareButton,
                       widgetMarketButton, moreButton] {
            button.usesFigmaStyle = true
            button.isBorderlessFigmaTile = true
            button.updateTooltip(button.toolTip ?? "")
            button.layer?.cornerRadius = 9
            inspectToolbar.addSubview(button)
        }
        focusButton.setDesignIcon("ToolbarFocus")
        compareButton.setDesignIcon("ToolbarCompare")
        widgetMarketButton.setDesignIcon("ToolbarGrid")
        canvas.addSubview(inspectToolbar)
        playButton.target = self; playButton.action = #selector(playTapped)
        playButton.usesFigmaStyle = true
        playButton.isBorderlessFigmaTile = true
        playButton.updateTooltip("Play".localized)
        playButton.contentTintColor = PanelStyle.accent
        timeline.onChange = { [weak self] value in self?.seek(to: value) }
        for label in [currentLabel, durationLabel] {
            label.font = PanelStyle.inspectFont(ofSize: 12, weight: label === currentLabel ? .medium : .regular)
            label.textColor = label === currentLabel ? PanelStyle.textSecondary : PanelStyle.textTertiary
            label.alignment = .center
        }
        [playButton, timeline, currentLabel, durationLabel].forEach { playbackBar.addSubview($0) }
        canvas.addSubview(playbackBar)
        filmstrip.onSelect = { [weak self] index in self?.selectVideo(index) }; canvas.addSubview(filmstrip)
        // The video fills the window; the controls float over it.
        inspectToolbar.isHidden = false; inspectToolbar.alphaValue = 1
        identityBar.isHidden = false; identityBar.alphaValue = 1
        filmstrip.isHidden = infos.count < 2; filmstrip.alphaValue = 1
        playbackBar.isHidden = false; playbackBar.alphaValue = 1
        infoPanel.autoresizingMask = [.width, .height]
        infoPanel.isHidden = true
        canvas.addSubview(infoPanel)
        captureFeedback.isHidden = true
        canvas.addSubview(captureFeedback, positioned: .above, relativeTo: nil)
        captureThumbnail.target = self
        captureThumbnail.action = #selector(captureThumbnailTapped)
        captureThumbnail.isHidden = true
        canvas.addSubview(captureThumbnail, positioned: .above, relativeTo: nil)
        render()
    }

    private func configureTraffic(_ button: NSButton, color: NSColor, tooltip: String, action: Selector) {
        button.isBordered = false
        button.title = ""
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = action
        button.wantsLayer = true
        button.layer?.backgroundColor = PanelStyle.resolvedCG(color)
        button.layer?.cornerRadius = 6
    }

    private var activeIndices: [Int] {
        if mode == .compare, let pair = compareIndices { return [pair.0, pair.1] }
        return infos.indices.contains(focusedIndex) ? [focusedIndex] : []
    }
    private var activeVideoFrame: NSRect { viewports.reduce(.zero) { $0.union($1.frame) } }

    private func layoutContent() {
        let b = canvas.bounds
        guard b.width > 0, b.height > 0 else { return }
        let sx = b.width / Self.designSize.width
        let sy = b.height / Self.designSize.height
        let scale = min(sx, sy)
        canvas.layer?.cornerRadius = 16 * scale
        canvas.layer?.borderWidth = max(1, scale)

        identityBar.frame = NSRect(x: 0, y: b.height - 44 * sy,
                                   width: b.width, height: 44 * sy)
        for (offset, button) in [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].enumerated() {
            button.frame = NSRect(x: 20 * sx + CGFloat(offset) * 26 * sx,
                                  y: 14 * sy, width: 12, height: 12)
            button.layer?.cornerRadius = 6
        }

        let toolbarScale = max(0.1, min(1, min((b.width - 16) / 274,
                                              (b.height - 16) / 54)))
        let toolbarW = 274 * toolbarScale
        inspectToolbar.frame = NSRect(x: (b.width - toolbarW) / 2,
                                      y: b.height - 78 * toolbarScale,
                                      width: toolbarW, height: 54 * toolbarScale)
        inspectToolbar.layer?.borderWidth = 1
        inspectToolbar.layer?.cornerRadius = 15 * toolbarScale
        func place(_ button: InspectToolbarButton, x: CGFloat) {
            button.frame = NSRect(x: x * toolbarScale, y: 8 * toolbarScale,
                                  width: 38 * toolbarScale, height: 38 * toolbarScale)
            button.layer?.cornerRadius = 9 * toolbarScale
            button.layer?.borderWidth = 0
            button.setSymbolPointSize(18 * toolbarScale)
        }
        place(captureButton, x: 14)
        place(focusButton, x: 66)
        place(compareButton, x: 118)
        place(widgetMarketButton, x: 170)
        place(moreButton, x: 222)

        let canvasW = max(0, b.width - (infoVisible ? 434 * sx : 0))
        let videoRect = NSRect(x: 0, y: 0, width: canvasW, height: b.height)
        infoPanel.frame = NSRect(x: canvasW, y: 0, width: 434 * sx, height: videoRect.height)
        infoPanel.isHidden = !infoVisible
        if mode == .compare, activeIndices.count == 2 {
            // Fit each complete video, then place the visible images beside
            // each other. Equal half-window viewports put a large empty band
            // between two portrait videos even though their pane gap is 2pt.
            let gap = 2 * scale
            let maxWidth = max(1, (videoRect.width - gap) / 2)
            func fittedSize(for slot: Int) -> CGSize {
                guard let index = activeIndices[safe: slot] else {
                    return CGSize(width: maxWidth, height: videoRect.height)
                }
                let natural = infos[index].dimensions
                    ?? viewports[safe: slot]?.videoSize
                    ?? .zero
                guard natural.width > 0, natural.height > 0 else {
                    return CGSize(width: maxWidth, height: videoRect.height)
                }
                let fit = min(maxWidth / natural.width, videoRect.height / natural.height)
                return CGSize(width: natural.width * fit, height: natural.height * fit)
            }
            let left = fittedSize(for: 0)
            let right = fittedSize(for: 1)
            // Keep the compare seam centered, as in Image Inspect. Any spare
            // width stays at the outside edges instead of between the videos.
            let seam = videoRect.midX
            viewports[safe: 0]?.frame = NSRect(x: seam - gap / 2 - left.width,
                                                y: videoRect.midY - left.height / 2,
                                                width: left.width, height: left.height)
            viewports[safe: 1]?.frame = NSRect(x: seam + gap / 2,
                                                y: videoRect.midY - right.height / 2,
                                                width: right.width, height: right.height)
        } else {
            viewports[safe: 0]?.frame = videoRect
            viewports[safe: 1]?.frame = .zero
        }

        let barWidth = min(1306 * sx, max(0, canvasW - 96 * sx))
        playbackBar.frame = NSRect(x: (canvasW - barWidth) / 2, y: 24 * sy,
                                   width: barWidth, height: 64 * sy)
        playbackBar.layer?.cornerRadius = 15 * scale
        let barScale = barWidth / 1306
        playButton.frame = NSRect(x: 16 * barScale, y: 13 * sy,
                                  width: 38 * barScale, height: 38 * sy)
        playButton.layer?.cornerRadius = 8 * scale
        timeline.frame = NSRect(x: 76 * barScale, y: 23 * sy,
                                width: max(1, 1070 * barScale), height: 18 * sy)
        currentLabel.font = PanelStyle.inspectFont(ofSize: 12 * sy, weight: .medium)
        durationLabel.font = PanelStyle.inspectFont(ofSize: 12 * sy)
        currentLabel.frame = NSRect(x: 1168 * barScale, y: 25 * sy,
                                    width: 42 * barScale, height: 15 * sy)
        durationLabel.frame = NSRect(x: 1224 * barScale, y: 25 * sy,
                                     width: 52 * barScale, height: 15 * sy)

        let count = max(1, infos.count)
        let filmWidth = min((CGFloat(count) * 96 + CGFloat(count - 1) * 10) * sx,
                            max(96 * sx, canvasW - 64 * sx))
        filmstrip.frame = NSRect(x: (canvasW - filmWidth) / 2,
                                 y: playbackBar.frame.maxY + 20 * sy,
                                 width: filmWidth, height: 96 * sy)
        captureFeedback.frame = videoRect
        let thumbnailSize = NSSize(width: 220 * scale, height: 125 * scale)
        captureThumbnail.contentWidth = thumbnailSize.width
        if !captureThumbnail.isHidden, pendingCaptureURL != nil {
            captureThumbnail.frame = NSRect(
                x: canvasW - 24 * sx - thumbnailSize.width,
                y: playbackBar.frame.maxY + 24 * sy,
                width: thumbnailSize.width, height: thumbnailSize.height
            )
        }
    }

    private func render() {
        generation = UUID(); frameCaptureGeneration = UUID(); shouldResumeAfterCapture = false
        removeObservers(); viewports.forEach { $0.pause(); $0.removeFromSuperview() }; viewports.removeAll(); isPlaying = false; currentTime = 0
        for index in activeIndices {
            let info = infos[index]
            let viewport = VideoInspectViewport(index: index, url: info.url)
            viewport.dropTarget = canvas
            viewport.onActionMenu = { [weak self] event in
                guard let self, let window = event.window else { return }
                if let compareIndices = self.compareIndices {
                    self.activeCompareSlot = compareIndices.0 == index ? 0 : 1
                    self.updateVideoCompareDimming()
                    self.refreshInfoPanel()
                }
                let origin = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
                self.presentMuteMenu(atScreenPoint: origin)
            }
            viewport.onActivate = { [weak self] in
                guard let self else { return }
                self.activeCompareSlot = self.compareIndices?.0 == index ? 0 : 1
                self.updateVideoCompareDimming()
                self.refreshInfoPanel()
            }
            viewport.onReady = { [weak self, weak viewport] in
                guard let self else { return }
                self.fitWindowToActiveVideosIfNeeded()
                self.layoutContent()
                if self.isPlaying { viewport?.play() }
            }
            viewport.onWebMMetadata = { [weak self] duration, size in
                guard let self, self.infos.indices.contains(index) else { return }
                self.durations[index] = duration
                self.infos[index].dimensions = size
                self.updateTimeline()
                self.layoutContent()
                self.refreshInfoPanel()
            }
            var needsWebMThumbnail = true
            viewport.onWebMFrameReady = { [weak self, weak viewport] in
                guard needsWebMThumbnail else { return }
                needsWebMThumbnail = false
                viewport?.captureFrame(at: 0) { [weak self] image in
                    guard let image else { return }
                    self?.filmstrip.setThumbnail(image, at: index)
                }
            }
            viewport.onTimeUpdate = { [weak self, weak viewport] time in
                guard let self, self.isPlaying, self.viewports.first === viewport else { return }
                self.currentTime = min(max(0, time), self.maximumDuration)
                self.updateTimeline()
            }
            viewport.onEnded = { [weak self] in self?.pausePlayback() }
            viewport.setCompareDimmed(mode == .compare && activeCompareSlot != (compareIndices?.0 == index ? 0 : 1))
            canvas.addSubview(viewport, positioned: .below, relativeTo: inspectToolbar); viewports.append(viewport)
            if !info.isLocal {
                let token = generation
                // Remote playback starts immediately above; persistent download
                // happens in parallel. Switch to the local cache at the same
                // timestamp when ready (or immediately on subsequent opens).
                RemoteMediaDiskCache.shared.downloadIfNeeded(info.url) { [weak self, weak viewport] cachedURL in
                    guard let self, self.generation == token else { return }
                    if let cachedURL {
                        viewport?.replaceSource(with: cachedURL)
                    }
                }
            }
        }
        // Keep all chrome above the AVPlayer surfaces after every mode switch.
        canvas.addSubview(identityBar, positioned: .above, relativeTo: nil)
        canvas.addSubview(playbackBar, positioned: .above, relativeTo: nil)
        canvas.addSubview(filmstrip, positioned: .above, relativeTo: nil)
        canvas.addSubview(infoPanel, positioned: .above, relativeTo: nil)
        canvas.addSubview(inspectToolbar, positioned: .above, relativeTo: nil)
        canvas.addSubview(captureFeedback, positioned: .above, relativeTo: nil)
        canvas.addSubview(captureThumbnail, positioned: .above, relativeTo: nil)
        focusButton.isEnabled = true
        compareButton.isEnabled = infos.count > 1
        focusButton.isActive = mode == .focus
        compareButton.isActive = mode == .compare
        revealButton.isEnabled = activeIndices.contains { infos[$0].isLocal }
        filmstrip.isHidden = infos.count < 2
        filmstrip.configure(infos: infos, selectedIndex: focusedIndex, compareIndices: mode == .compare ? compareIndices : nil)
        refreshInfoPanel()
        fitWindowToActiveVideosIfNeeded()
        updateTimeline(); layoutContent(); loadDurations(); startPlaybackImmediately()
    }

    private func startPlaybackImmediately() {
        guard !viewports.isEmpty else { return }
        isPlaying = true
        viewports.forEach { $0.play() }
        installObserver()
        updateTimeline()
    }

    private func fitWindowToActiveVideosIfNeeded() {
        let sizes: [CGSize] = activeIndices.enumerated().compactMap { offset, index in
            let size = infos[safe: index]?.dimensions ?? viewports[safe: offset]?.videoSize
            guard let size, size.width > 0, size.height > 0 else { return nil }
            return size
        }
        guard sizes.count == activeIndices.count, !sizes.isEmpty else { return }

        let targetSize: CGSize
        if mode == .compare, sizes.count == 2 {
            let height = max(sizes[0].height, sizes[1].height)
            let width = sizes.reduce(CGFloat(0)) {
                $0 + $1.width * height / max(1, $1.height)
            } + 2
            targetSize = CGSize(width: width, height: height)
        } else {
            targetSize = sizes[0]
        }

        let signature = "\(mode)-\(targetSize.width.rounded())x\(targetSize.height.rounded())"
        guard signature != fittedVideoSignature else { return }
        fittedVideoSignature = signature

        let aspect = targetSize.width / targetSize.height
        contentAspectRatio = NSSize(width: aspect, height: 1)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = ScreenManager.shared.screenForMouseLocation(center)
                ?? self.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let downscale = min(1, visible.width * 0.96 / targetSize.width,
                            visible.height * 0.96 / targetSize.height)
        let contentSize = NSSize(width: targetSize.width * downscale,
                                 height: targetSize.height * downscale)
        let frameSize = frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        var origin = NSPoint(x: center.x - frameSize.width / 2,
                             y: center.y - frameSize.height / 2)
        origin.x = max(visible.minX, min(origin.x, visible.maxX - frameSize.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - frameSize.height))
        setFrame(NSRect(origin: origin, size: frameSize), display: true, animate: false)
    }

    private func loadDurations() {
        let token = generation
        for (index, info) in infos.enumerated() {
            if info.url.pathExtension.lowercased() == "webm" { continue }
            let asset = AVURLAsset(url: info.url)
            Task { [weak self] in
                let duration = (try? await asset.load(.duration))?.seconds ?? info.duration ?? 0
                var metadata = VideoTechnicalMetadata()
                var dimensions = info.dimensions
                var fileSize = info.fileSize
                if let tracks = try? await asset.load(.tracks) {
                    if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                        let fps = (try? await videoTrack.load(.nominalFrameRate)) ?? 0
                        if fps > 0 { metadata.fps = fps }
                        metadata.videoBitrate = try? await videoTrack.load(.estimatedDataRate)
                        if let descriptions = try? await videoTrack.load(.formatDescriptions),
                           let description = descriptions.first {
                            metadata.videoCodec = Self.videoCodecName(for: CMFormatDescriptionGetMediaSubType(description))
                        }
                        if dimensions == nil,
                           let natural = try? await videoTrack.load(.naturalSize),
                           let transform = try? await videoTrack.load(.preferredTransform) {
                            let size = natural.applying(transform)
                            dimensions = CGSize(width: abs(size.width), height: abs(size.height))
                        }
                    }
                    if let audioTrack = tracks.first(where: { $0.mediaType == .audio }),
                       let descriptions = try? await audioTrack.load(.formatDescriptions),
                       let description = descriptions.first {
                        metadata.audioCodec = Self.audioCodecName(for: CMFormatDescriptionGetMediaSubType(description))
                    }
                }
                if fileSize == nil, info.isLocal,
                   let attrs = try? FileManager.default.attributesOfItem(atPath: info.url.path) {
                    fileSize = (attrs[.size] as? NSNumber)?.int64Value
                }
                await MainActor.run {
                    guard let self, self.generation == token,
                          self.infos.indices.contains(index) else { return }
                    self.durations[index] = max(0, duration)
                    if self.videoMetadata.indices.contains(index) { self.videoMetadata[index] = metadata }
                    if let dimensions, self.infos[index].dimensions == nil { self.infos[index].dimensions = dimensions }
                    if let fileSize, self.infos[index].fileSize == nil { self.infos[index].fileSize = fileSize }
                    self.fitWindowToActiveVideosIfNeeded()
                    self.updateTimeline()
                    self.layoutContent()
                    self.refreshInfoPanel()
                }
            }
        }
        installObserver()
    }
    private var maximumDuration: Double { durations.max() ?? 0 }
    private func installObserver() {
        guard timeObserver == nil, let player = viewports.first?.player else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600), queue: .main) { [weak self] time in guard let self, self.isPlaying else { return }; self.currentTime = min(max(0, time.seconds), self.maximumDuration); self.updateTimeline() }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in self?.pausePlayback() }
    }
    private func updateTimeline() {
        timeline.maximum = maximumDuration
        timeline.value = currentTime
        currentLabel.stringValue = Self.formatTime(currentTime)
        durationLabel.stringValue = Self.formatTime(maximumDuration)
        playButton.setSymbol(isPlaying ? "pause.fill" : "play.fill")
    }
    @objc private func playTapped() { isPlaying ? pausePlayback() : playPlayback() }
    private func playPlayback() {
        seek(to: currentTime) { [weak self] in
            guard let self else { return }
            // setRate(_:atHostTime:) throws when an AVPlayer has no usable
            // host-time anchor. Exact-seek both first, then start them in this
            // single main-thread turn with buffering waits disabled.
            self.viewports.forEach { $0.play() }
            self.isPlaying = true
            self.updateTimeline()
        }
    }
    private func pausePlayback() { viewports.forEach { $0.pause() }; isPlaying = false; updateTimeline() }
    private func seek(to time: Double, completion: (() -> Void)? = nil) {
        currentTime = min(max(0, time), maximumDuration); let group = DispatchGroup()
        for (offset, viewport) in viewports.enumerated() {
            let index = activeIndices[safe: offset] ?? focusedIndex
            let limit = durations[safe: index] ?? maximumDuration
            group.enter()
            viewport.seek(to: min(currentTime, limit)) { group.leave() }
        }
        updateTimeline(); group.notify(queue: .main) { completion?() }
    }
    @objc private func focusTapped() { mode = .focus; pausePlayback(); render() }
    @objc private func compareTapped() { guard infos.count > 1 else { return }; if compareIndices == nil { compareIndices = (focusedIndex, focusedIndex == 0 ? 1 : 0) }; mode = .compare; pausePlayback(); render() }
    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }
    @objc private func revealTapped() { for index in activeIndices where infos[index].isLocal { NSWorkspace.shared.activateFileViewerSelecting([infos[index].url]); break } }
    @objc private func pinTapped() {
        isPinned.toggle()
        pinButton.isActive = isPinned
        pinButton.updateTooltip((isPinned ? "Unpin" : "Pin on Top").localized)
        level = isPinned ? .floating : .normal
    }
    @objc private func widgetMarketTapped() { WidgetMarketPanel.shared.toggle(from: self) }
    @objc private func moreTapped() {
        actionsPanel?.dismissChain()
        let panel = ActionMenuPanel(entries: buildMoreEntries(), style: .more)
        actionsPanel = panel
        // Anchor the menu to the toolbar's bottom-right corner so it drops
        // down from the toolbar with an 8pt gap and right-aligns with it.
        let windowPoint = inspectToolbar.convert(NSPoint(x: inspectToolbar.bounds.maxX, y: 0), to: nil)
        let screenPoint = convertToScreen(NSRect(origin: windowPoint, size: .zero)).origin
        panel.presentBelowToolbar(at: screenPoint)
    }
    @objc private func infoTapped() {
        infoVisible.toggle()
        infoPanel.isHidden = !infoVisible
        refreshInfoPanel()
        layoutContent()
    }
    private func refreshInfoPanel() {
        guard infoVisible else { return }
        guard let index = activeIndices[safe: mode == .compare ? activeCompareSlot : 0],
              infos.indices.contains(index) else { return }
        infoPanel.update(info: infos[index], duration: durations[safe: index] ?? 0,
                         metadata: videoMetadata[safe: index] ?? nil)
    }
    @objc private func replayTapped() { pausePlayback(); currentTime = 0; playPlayback() }
    @objc private func captureTapped() {
        // Freeze and exactly seek every player to the same master time before
        // reading pixels. Generating frames while playback continues returns
        // neighboring keyframes at different moments.
        let playerTime = viewports.first?.currentTime ?? currentTime
        let captureTime = playerTime.isFinite ? max(0, playerTime) : max(0, currentTime)
        shouldResumeAfterCapture = shouldResumeAfterCapture || isPlaying
        let captureGeneration = generation
        frameCaptureGeneration = UUID()
        let frameCaptureToken = frameCaptureGeneration
        pausePlayback()
        seek(to: captureTime) { [weak self] in
            guard let self, self.generation == captureGeneration,
                  self.frameCaptureGeneration == frameCaptureToken else { return }
            let resumePlayback = self.shouldResumeAfterCapture
            self.shouldResumeAfterCapture = false
            self.finishCapture(at: captureTime, resumePlayback: resumePlayback)
        }
    }
    private func finishCapture(at time: Double, resumePlayback: Bool) {
        let token = generation
        captureCurrentFrame(at: time) { [weak self] image in
            guard let self, self.generation == token else { return }
            self.completeCapture(image: image, at: time, resumePlayback: resumePlayback)
        }
    }
    private func completeCapture(image: NSImage?, at time: Double, resumePlayback: Bool) {
        defer {
            if resumePlayback {
                viewports.forEach { $0.play() }
                isPlaying = true
                updateTimeline()
            }
        }
        guard let image else { return }
        NSSound(named: "Grab")?.play()
        captureFeedback.flash()
        // Keep the captured frame ready for the thumbnail's existing Image
        // Inspect handoff. A second capture replaces the pending preview.
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("capture-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
        } catch {
            Logger.error("Video capture write failed: \(error.localizedDescription)")
            return
        }
        showCaptureThumbnail(image: image, time: time, url: url)
    }
    private func showCaptureThumbnail(image: NSImage, time: Double, url: URL) {
        captureThumbnailTimer?.invalidate()
        if let previous = pendingCaptureURL { try? FileManager.default.removeItem(at: previous) }
        pendingCaptureURL = url
        captureThumbnailGeneration = UUID()
        captureThumbnail.layer?.removeAllAnimations()
        captureThumbnail.capturedImage = image
        captureThumbnail.timecode = Self.thumbnailTimecode(time)
        captureThumbnail.alphaValue = 1
        captureThumbnail.isHidden = false
        layoutContent()

        let token = captureThumbnailGeneration
        let timer = Timer(timeInterval: 10, repeats: false) { [weak self] _ in
            guard let self, self.captureThumbnailGeneration == token else { return }
            self.hideCaptureThumbnail()
        }
        captureThumbnailTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    @objc private func captureThumbnailTapped() {
        guard let url = pendingCaptureURL else { return }
        captureThumbnailTimer?.invalidate()
        captureThumbnailTimer = nil
        pendingCaptureURL = nil
        captureThumbnailGeneration = UUID()
        captureThumbnail.isHidden = true
        captureThumbnail.capturedImage = nil
        // Finish the thumbnail's mouse event before Image Inspect takes focus.
        DispatchQueue.main.async { [weak self] in self?.onCaptureFrame?(url) }
    }
    private func hideCaptureThumbnail() {
        captureThumbnailTimer?.invalidate()
        captureThumbnailTimer = nil
        let expiredURL = pendingCaptureURL
        pendingCaptureURL = nil
        let token = captureThumbnailGeneration
        let frame = captureThumbnail.frame
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            captureThumbnail.animator().frame = NSRect(x: frame.maxX, y: frame.minY,
                                                       width: 0, height: frame.height)
        }) { [weak self] in
            if let expiredURL { try? FileManager.default.removeItem(at: expiredURL) }
            guard let self, self.captureThumbnailGeneration == token else { return }
            self.captureThumbnail.isHidden = true
            self.captureThumbnail.capturedImage = nil
        }
    }
    private static func thumbnailTimecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    private func captureCurrentFrame(at time: Double, completion: @escaping (NSImage?) -> Void) {
        guard !viewports.isEmpty else { completion(nil); return }
        var captured = Array<NSImage?>(repeating: nil, count: viewports.count)
        let group = DispatchGroup()
        for (offset, viewport) in viewports.enumerated() {
            let index = activeIndices[safe: offset] ?? focusedIndex
            let limit = durations[safe: index] ?? maximumDuration
            group.enter()
            viewport.captureFrame(at: min(max(0, time), limit)) { image in
                captured[offset] = image
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let frames = captured.compactMap { $0 }
            guard !frames.isEmpty else { completion(nil); return }
            if frames.count == 1 { completion(frames[0]); return }
            let gap: CGFloat = 2
            let height = frames.map(\.size.height).max() ?? 1
            let width = frames.reduce(0) { $0 + ($1.size.width * height / max(1, $1.size.height)) } + gap
            let output = NSImage(size: NSSize(width: width, height: height))
            output.lockFocus()
            NSColor.black.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: output.size)).fill()
            var x: CGFloat = 0
            for frame in frames {
                let frameWidth = frame.size.width * height / max(1, frame.size.height)
                frame.draw(in: NSRect(x: x, y: 0, width: frameWidth, height: height),
                           from: .zero, operation: .sourceOver, fraction: 1)
                x += frameWidth + gap
            }
            output.unlockFocus()
            completion(output)
        }
    }
    private func selectVideo(_ index: Int) { guard infos.indices.contains(index) else { return }; if mode == .compare, let pair = compareIndices { if activeCompareSlot == 0, index != pair.1 { compareIndices = (index, pair.1) } else if activeCompareSlot == 1, index != pair.0 { compareIndices = (pair.0, index) } } else { focusedIndex = index }; pausePlayback(); render() }

    /// Accept a video file dragged onto the window. The file is appended to
    /// the end of the filmstrip; which on-screen slot shows it depends on the
    /// current mode:
    ///   - Focus: play the dropped video directly.
    ///   - Compare: replace the side the drop landed on.
    /// The toolbar More button and right-click share one menu. Video
    /// information is available here instead of occupying a toolbar tile.
    private func buildMoreEntries() -> [ActionMenuEntry] {
        var entries = [
            ActionMenuEntry(title: "Video information".localized,
                            action: { [weak self] in self?.infoTapped() }),
            .separator(),
        ]
        // Focus toggles one player; Compare offers independent mute control.
        if mode == .compare, viewports.count == 2 {
            let leftMuted = viewports[0].isMuted
            let rightMuted = viewports[1].isMuted
            entries.append(ActionMenuEntry(title: (leftMuted ? "Unmute Left" : "Mute Left").localized,
                                           action: { [weak self] in self?.toggleMute(slot: 0) }))
            entries.append(ActionMenuEntry(title: (rightMuted ? "Unmute Right" : "Mute Right").localized,
                                           action: { [weak self] in self?.toggleMute(slot: 1) }))
        } else if let viewport = viewports.first {
            entries.append(ActionMenuEntry(title: (viewport.isMuted ? "Unmute" : "Mute").localized,
                                           action: { [weak viewport] in
                guard let viewport else { return }
                viewport.setMuted(!viewport.isMuted)
            }))
        }
        entries.append(.separator())
        entries.append(ActionMenuEntry(title: "Replay".localized,
                                       action: { [weak self] in self?.replayTapped() }))
        let canReveal = activeIndices.contains { infos[$0].isLocal }
        entries.append(ActionMenuEntry(title: "Reveal in Finder".localized, enabled: canReveal,
                                       action: { [weak self] in self?.revealTapped() }))
        entries.append(ActionMenuEntry(title: (isPinned ? "Unpin" : "Pin on Top").localized,
                                       action: { [weak self] in self?.pinTapped() }))
        let widgets = WidgetRegistry.shared.compatible(with: "video")
        if !widgets.isEmpty {
            entries.append(.separator())
            entries.append(ActionMenuEntry(title: "Widgets".localized, submenu: widgets.compactMap { widget in
                let commands = widget.commands.filter { $0.inputTypes.contains("video") }
                guard !commands.isEmpty else { return nil }
                func entry(_ command: WidgetCommand) -> ActionMenuEntry {
                    let currentIndex = activeIndices[safe: mode == .compare ? activeCompareSlot : 0]
                    let duplicate = currentIndex.flatMap { infos[safe: $0] }.map { info in
                        WidgetTaskManager.shared.activeRecords(for: info.url).contains {
                            $0.widgetID == widget.id && $0.commandID == command.id
                        }
                    } ?? false
                    return ActionMenuEntry(title: command.name, enabled: !duplicate,
                                           action: { [weak self] in self?.runWidget(widget: widget, command: command) })
                }
                if commands.count == 1 { return entry(commands[0]) }
                return ActionMenuEntry(title: widget.name, submenu: commands.map(entry))
            }))
        }
        return entries
    }

    private func presentMuteMenu(atScreenPoint point: NSPoint) {
        actionsPanel?.dismissChain()
        let panel = ActionMenuPanel(entries: buildMoreEntries())
        actionsPanel = panel
        panel.present(at: point)
    }

    private func toggleMute(slot: Int) {
        guard viewports.indices.contains(slot) else { return }
        let viewport = viewports[slot]
        viewport.setMuted(!viewport.isMuted)
    }

    private func runWidget(widget: WidgetManifest, command: WidgetCommand) {
        guard let index = activeIndices[safe: mode == .compare ? activeCompareSlot : 0],
              infos.indices.contains(index) else { return }
        _ = WidgetTaskManager.shared.start(widget: widget, command: command, media: infos[index])
    }

    private func handleDroppedVideo(url: URL, at point: NSPoint) {
        infos.append(MediaInfo(url: url, isLocal: url.isFileURL, kind: .video))
        durations.append(0)
        videoMetadata.append(nil)
        let newIndex = infos.count - 1
        if mode == .compare, let pair = compareIndices {
            let slot = viewports[safe: 0]?.frame.contains(point) == true ? 0 : 1
            activeCompareSlot = slot
            compareIndices = slot == 0 ? (newIndex, pair.1) : (pair.0, newIndex)
        } else {
            focusedIndex = newIndex
        }
        pausePlayback()
        render()
    }

    /// ⌘V uses the same PathDetector classification as selection activation.
    /// Duplicate URLs focus the existing video; new URLs append and display.
    private func pasteRemoteVideoFromClipboard() -> Bool {
        guard let text = ImageInspectWindow.clipboardText(),
              let info = pathDetector.detectAll(text)
                .compactMap(MediaInfo.from)
                .first(where: { $0.kind == .video && !$0.isLocal }) else { return false }
        let identity = info.url.absoluteURL.absoluteString
        if let index = infos.firstIndex(where: { $0.url.absoluteURL.absoluteString == identity }) {
            focusedIndex = index
        } else {
            infos.append(info)
            durations.append(0)
            videoMetadata.append(nil)
            focusedIndex = infos.count - 1
        }
        mode = .focus
        compareIndices = nil
        pausePlayback()
        render()
        Logger.info("VideoCompareWindow: pasted remote video")
        return true
    }
    private func updateVideoCompareDimming() {
        guard mode == .compare else {
            viewports.forEach { $0.setCompareDimmed(false) }
            return
        }
        for (offset, viewport) in viewports.enumerated() {
            viewport.setCompareDimmed(offset != activeCompareSlot)
        }
    }
    private func removeObservers() { if let observer = timeObserver, let player = viewports.first?.player { player.removeTimeObserver(observer) }; timeObserver = nil; if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }; endObserver = nil }
    func windowWillClose(_ notification: Notification) {
        pausePlayback(); removeObservers(); actionsPanel?.dismissChain(); actionsPanel = nil
        infoVisible = false; generation = UUID()
        frameCaptureGeneration = UUID()
        shouldResumeAfterCapture = false
        captureThumbnailTimer?.invalidate(); captureThumbnailTimer = nil
        captureThumbnailGeneration = UUID()
        if let pendingCaptureURL { try? FileManager.default.removeItem(at: pendingCaptureURL) }
        pendingCaptureURL = nil
        captureThumbnail.capturedImage = nil
    }
    private static func formatTime(_ seconds: Double) -> String { let total = max(0, Int(seconds.rounded(.down))); return String(format: "%d:%02d", total / 60, total % 60) }

    static func videoCodecName(for subType: FourCharCode) -> String {
        switch fourCCString(subType) {
        case "avc1", "avc3": return "H.264 / AVC"
        case "hvc1", "hev1": return "H.265 / HEVC"
        case "vp09": return "VP9"
        case "av01": return "AV1"
        case "mp4v": return "MPEG-4 Part 2"
        case "apch": return "ProRes 422 HQ"
        case "apcn": return "ProRes 422"
        case "apcs": return "ProRes 422 LT"
        case "apco": return "ProRes 422 Proxy"
        case "ap4h", "ap4x": return "ProRes 4444"
        case "dvh1", "dvhe": return "Dolby Vision"
        case "jpeg": return "Motion JPEG"
        default: return fourCCString(subType).trimmingCharacters(in: .whitespaces)
        }
    }

    static func audioCodecName(for subType: FourCharCode) -> String {
        switch fourCCString(subType) {
        case "mp4a": return "AAC"
        case "ac-3": return "AC-3"
        case "ec-3": return "E-AC-3"
        case "alac": return "ALAC"
        case "lpcm", "sowt", "twos": return "LPCM"
        case "opus": return "Opus"
        case "flac": return "FLAC"
        default: return fourCCString(subType).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
                     UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", code)
    }
}

private final class VideoInspectViewport: NSView {
    let index: Int
    let player: AVPlayer?
    private let playerView: AVPlayerView?
    private let webMView: WebMVideoView?
    private let muteButton = InspectToolbarButton(symbol: "speaker.slash.fill", tooltip: "Mute".localized)
    private let compareDimmer = CALayer()
    private let loadingView = FocusSweepLoadingView(frame: .zero)
    private let failureView = LoadFailedAnimationView(frame: .zero)
    private var statusObservation: NSKeyValueObservation?
    var onActivate: (() -> Void)?
    var onReady: (() -> Void)?
    var onWebMMetadata: ((Double, CGSize) -> Void)?
    var onWebMFrameReady: (() -> Void)?
    var onTimeUpdate: ((Double) -> Void)?
    var onEnded: (() -> Void)?
    var videoSize: CGSize { webMView?.videoSize ?? player?.currentItem?.presentationSize ?? .zero }
    var currentTime: Double { webMView?.videoTime ?? player?.currentTime().seconds ?? 0 }
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
            nativePlayer.isMuted = true
            nativePlayer.automaticallyWaitsToMinimizeStalling = false
            player = nativePlayer
            let nativeView = PassthroughVideoPlayerView(frame: .zero)
            nativeView.controlsStyle = .none
            nativeView.videoGravity = .resizeAspect
            nativeView.player = nativePlayer
            nativeView.registerForDraggedTypes(MediaDropCanvasView.videoDraggedTypes)
            playerView = nativeView
            webMView = nil
        }
        super.init(frame: .zero)
        registerForDraggedTypes(MediaDropCanvasView.videoDraggedTypes)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = PanelStyle.inspectCanvas.cgColor
        if let playerView {
            playerView.wantsLayer = true
            playerView.layer?.masksToBounds = true
            addSubview(playerView)
        }
        if let webMView {
            webMView.onReady = { [weak self] duration, size in
                guard let self else { return }
                self.loadingView.setLoading(false)
                self.failureView.isHidden = true
                self.onWebMMetadata?(duration, size)
                self.onReady?()
            }
            webMView.onTimeUpdate = { [weak self] time in self?.onTimeUpdate?(time) }
            webMView.onEnded = { [weak self] in self?.onEnded?() }
            webMView.onFrameReady = { [weak self] in self?.onWebMFrameReady?() }
            webMView.onFailure = { [weak self] in
                self?.loadingView.setLoading(false)
                self?.failureView.isHidden = false
            }
            addSubview(webMView)
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
        if player != nil { observePlayerItem() }
        else { loadingView.setLoading(true) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        playerView?.frame = bounds
        webMView?.frame = bounds
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
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropTarget?.acceptsDragging(sender) == true ? .copy : [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropTarget?.acceptsDragging(sender) == true ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { dropTarget?.performDrop(sender) == true }
    func replaceSource(with url: URL) {
        if let webMView { webMView.replaceSource(with: url); return }
        guard let player else { return }
        let time = player.currentTime()
        let wasPlaying = player.rate != 0
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        observePlayerItem()
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            if wasPlaying { self?.player?.playImmediately(atRate: 1) }
        }
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
    private func updateMuteButton() { muteButton.setSymbol(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"); muteButton.updateTooltip(isMuted ? "Mute".localized : "Unmute".localized); muteButton.isActive = !isMuted }
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
        guard let cgImage = try? generator.copyCGImage(at: target, actualTime: nil) else {
            completion(nil); return
        }
        completion(NSImage(cgImage: cgImage,
                           size: NSSize(width: cgImage.width, height: cgImage.height)))
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
private final class PassthroughVideoPlayerView: AVPlayerView {
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

/// WebKit decodes WebM on macOS, while AVFoundation cannot open its container.
/// A small local page owns the video element so its layout and playback can be
/// controlled without the media document's built-in presentation overriding it.
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
    private var muted = true
    private var loadToken = UUID()
    private var wrapperDirectory: URL?
    private var sourceURL: URL
    private var usingFallback = false
    private var fallbackDirectory: URL?
    private var fallbackProcess: Process?

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
        registerForDraggedTypes(MediaDropCanvasView.videoDraggedTypes)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        loadSource(url)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if fallbackProcess?.isRunning == true { fallbackProcess?.terminate() }
        if let wrapperDirectory { try? FileManager.default.removeItem(at: wrapperDirectory) }
        if let fallbackDirectory { try? FileManager.default.removeItem(at: fallbackDirectory) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
          video.muted = true;
          video.pause();
          const send = (type, extra = {}) => window.webkit.messageHandlers.glanceVideo.postMessage({type, ...extra});
          video.addEventListener('loadedmetadata', () => { fit(); send('ready', {
            duration: video.duration, width: video.videoWidth, height: video.videoHeight
          }); });
          video.addEventListener('canplay', () => { fit(); send('frameReady'); });
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
                    <body><video muted playsinline preload="auto"></video>
                    <script>document.querySelector('video').src = \(encodedSource);</script></body></html>
                    """
                let page = directory.appendingPathComponent("index.html")
                try html.write(to: page, atomically: true, encoding: .utf8)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadToken == token else {
                        try? FileManager.default.removeItem(at: directory)
                        return
                    }
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
                    Logger.error("WebMVideoView: could not prepare \(url.lastPathComponent): \(error.localizedDescription)")
                    self.onFailure?()
                }
            }
        }
    }
    func replaceSource(with url: URL) {
        pendingSeek = (videoTime, nil)
        if fallbackProcess?.isRunning == true { fallbackProcess?.terminate() }
        fallbackProcess = nil
        if let fallbackDirectory { try? FileManager.default.removeItem(at: fallbackDirectory) }
        fallbackDirectory = nil
        usingFallback = false
        sourceURL = url
        loadSource(url)
    }
    private static func ffmpegURL() -> URL? {
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
        Logger.info("WebMVideoView: converting unsupported WebM \(original.lastPathComponent)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            process.waitUntilExit()
            DispatchQueue.main.async {
                guard let self, self.loadToken == token else {
                    try? FileManager.default.removeItem(at: directory)
                    return
                }
                self.fallbackProcess = nil
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
        guard isReady else { return }
        evaluateJavaScript("document.querySelector('video')?.play().catch(() => {})")
    }
    func pauseVideo() {
        wantsPlay = false
        evaluateJavaScript("document.querySelector('video')?.pause()")
    }
    func seek(to seconds: Double, completion: (() -> Void)? = nil) {
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
        evaluateJavaScript("document.querySelector('video').muted = \(value ? "true" : "false")")
    }
    var isVideoMuted: Bool { muted }
    func captureFrame(_ completion: @escaping (NSImage?) -> Void) {
        let script = """
            (() => { const v = document.querySelector('video');
              if (!v || !v.videoWidth || !v.videoHeight) return null;
              const c = document.createElement('canvas');
              c.width = v.videoWidth; c.height = v.videoHeight;
              c.getContext('2d').drawImage(v, 0, 0);
              return c.toDataURL('image/png'); })()
            """
        evaluateJavaScript(script) { [weak self] result, _ in
            if let dataURL = result as? String,
               let data = Data(base64Encoded: String(dataURL.split(separator: ",", maxSplits: 1).last ?? "")),
               let image = NSImage(data: data) {
                completion(image)
            } else {
                self?.takeSnapshot(with: nil) { image, _ in completion(image) }
            }
        }
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            releaseEmbeddedDragDestinations()
            isReady = true
            videoDuration = body["duration"] as? Double ?? 0
            videoSize = CGSize(width: body["width"] as? Double ?? 0,
                               height: body["height"] as? Double ?? 0)
            onReady?(videoDuration, videoSize)
            if let (time, completion) = pendingSeek {
                pendingSeek = nil
                seek(to: time, completion: completion)
            }
            if wantsPlay { playVideo() }
            if !muted { setVideoMuted(false) }
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
            releaseEmbeddedDragDestinations()
            if !wantsPlay { pauseVideo() }
            onFrameReady?()
        case "error":
            Logger.warning("WebMVideoView: media element failed (code \(body["code"] ?? 0)); \(body["message"] ?? "")")
            if !transcodeUnsupportedWebM() { onFailure?() }
        default: break
        }
    }
}

private final class WeakWebMMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: WebMVideoView?
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

private final class WarmVideoTimeline: NSView {
    var value = 0.0 { didSet { needsDisplay = true } }; var maximum = 1.0 { didSet { needsDisplay = true } }; var onChange: ((Double) -> Void)?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { let track = NSRect(x: 2, y: bounds.midY - 2, width: max(1, bounds.width - 4), height: 4); PanelStyle.inspectLine.setFill(); NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill(); let f = maximum > 0 ? min(1, max(0, value / maximum)) : 0; PanelStyle.accent.setFill(); NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * f, height: track.height), xRadius: 2, yRadius: 2).fill(); NSBezierPath(ovalIn: NSRect(x: track.minX + track.width * f - 7, y: bounds.midY - 7, width: 14, height: 14)).fill() }
    override func mouseDown(with event: NSEvent) { update(event) }; override func mouseDragged(with event: NSEvent) { update(event) }
    private func update(_ event: NSEvent) { let x = convert(event.locationInWindow, from: nil).x; let f = min(1, max(0, (x - 2) / max(1, bounds.width - 4))); onChange?(f * maximum) }
}

private final class VideoFilmstripView: NSView {
    var onSelect: ((Int) -> Void)?; private var infos: [MediaInfo] = []; private var selectedIndex = 0; private var compareIndices: (Int, Int)?
    func configure(infos: [MediaInfo], selectedIndex: Int, compareIndices: (Int, Int)?) { self.infos = infos; self.selectedIndex = selectedIndex; self.compareIndices = compareIndices; rebuild() }
    func setThumbnail(_ image: NSImage, at index: Int) {
        (subviews[safe: index] as? VideoFilmstripItem)?.setThumbnail(image)
    }
    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }; required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        guard !infos.isEmpty else { return }
        for index in infos.indices {
            let item = VideoFilmstripItem(frame: .zero)
            item.configure(selected: compareIndices == nil && index == selectedIndex,
                            compared: compareIndices.map { $0.0 == index || $0.1 == index } ?? false)
            item.toolTip = infos[index].filename
            item.setAccessibilityLabel(infos[index].filename)
            item.loadThumbnail(from: infos[index].url)
            item.onClick = { [weak self] in self?.onSelect?(index) }
            addSubview(item)
        }
        layoutItems()
    }
    private func layoutItems() {
        let count = subviews.count
        guard count > 0 else { return }
        let gap: CGFloat = 10
        let width = min(96, max(24, (bounds.width - CGFloat(count - 1) * gap) / CGFloat(count)))
        var x = (bounds.width - CGFloat(count) * width - CGFloat(count - 1) * gap) / 2
        for item in subviews {
            item.frame = NSRect(x: x, y: (bounds.height - width) / 2, width: width, height: width)
            x += width + gap
        }
    }
    override func layout() { super.layout(); layoutItems() }
}
private final class VideoFilmstripItem: NSView {
    var onClick: (() -> Void)?
    private let imageView = VideoThumbnailImageView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        imageView.contentTintColor = PanelStyle.textTertiary
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    // Selection is communicated by the warm-cue border only (mirrors the image
    // filmstrip); the frosted background stays the same either way.
    func configure(selected: Bool, compared: Bool) { layer?.borderWidth = selected || compared ? 2 : 1; layer?.borderColor = PanelStyle.resolvedCG(selected || compared ? PanelStyle.accent : PanelStyle.inspectLine); setAccessibilityElement(true); setAccessibilityRole(.button) }
    func setThumbnail(_ image: NSImage) { imageView.image = image }
    func loadThumbnail(from url: URL) { DispatchQueue.global(qos: .userInitiated).async { [weak self] in let generator = AVAssetImageGenerator(asset: AVAsset(url: url)); generator.appliesPreferredTrackTransform = true; guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return }; DispatchQueue.main.async { self?.imageView.image = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height))) } } }
    override func layout() { super.layout(); layer?.cornerRadius = 9 * bounds.width / 96; imageView.frame = bounds.insetBy(dx: 5 * bounds.width / 96, dy: 5 * bounds.height / 96) }; override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

private final class VideoThumbnailImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class VideoTitlebar: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) }
        else { window?.performDrag(with: event) }
    }
}

private final class VideoPlaybackBar: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 22 / 255, green: 23 / 255,
                                         blue: 25 / 255, alpha: 0.88).cgColor
        layer?.cornerRadius = 15
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.24).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        layer?.shadowRadius = 12
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class VideoInformationView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Video Information".localized)
    private let keys = ["Dimensions", "Duration", "Codec", "Frame rate", "Audio", "Bitrate"]
    private var keyLabels: [NSTextField] = []
    private var valueLabels: [NSTextField] = []
    private var dividers: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        addSubview(titleLabel)
        for key in keys {
            let label = NSTextField(labelWithString: key.localized)
            label.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
            label.textColor = PanelStyle.textTertiary
            addSubview(label)
            keyLabels.append(label)
            let value = NSTextField(labelWithString: "—")
            value.font = PanelStyle.inspectFont(ofSize: 13)
            value.textColor = PanelStyle.textPrimary
            value.lineBreakMode = .byTruncatingMiddle
            value.isSelectable = true
            addSubview(value)
            valueLabels.append(value)
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
            addSubview(line)
            dividers.append(line)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let sx = bounds.width / 434, sy = bounds.height / 847
        let scale = min(sx, sy)
        layer?.borderWidth = max(1, scale)
        func topFrame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * sx, y: bounds.height - (y + h) * sy,
                   width: w * sx, height: h * sy)
        }
        titleLabel.font = PanelStyle.inspectFont(ofSize: 17 * scale, weight: .semibold)
        titleLabel.frame = topFrame(36, 24, 362, 21)
        for index in keys.indices {
            let y = CGFloat(84 + index * 38)
            keyLabels[index].font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .medium)
            valueLabels[index].font = PanelStyle.inspectFont(ofSize: 13 * scale)
            keyLabels[index].frame = topFrame(36, y, 124, 16)
            valueLabels[index].frame = topFrame(174, y, 220, 16)
            dividers[index].frame = topFrame(36, y + 30, 362, 1)
        }
    }

    func update(info: MediaInfo, duration: Double, metadata: VideoTechnicalMetadata?) {
        let dimensions = info.dimensions.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "—"
        let time = duration > 0 ? String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60) : "—"
        let fps = metadata?.fps.map { String(format: "%g fps", Double($0)) } ?? "—"
        let audio = metadata?.audioCodec ?? "—"
        let bitrate: String
        if let value = metadata?.videoBitrate, value > 0 {
            bitrate = value >= 1_000_000
                ? String(format: "%.1f Mbps", Double(value) / 1_000_000)
                : String(format: "%.0f kbps", Double(value) / 1_000)
        } else { bitrate = "—" }
        let values = [dimensions, time, metadata?.videoCodec ?? "—", fps, audio, bitrate]
        for (label, value) in zip(valueLabels, values) { label.stringValue = value }
    }
}

/// A captured still that remains clickable until the ten-second timeout.
/// During dismissal the view's right edge stays fixed while its width shrinks;
/// drawing at a fixed content width clips the still from left to right.
private final class CaptureThumbnailButton: NSButton {
    var contentWidth: CGFloat = 220 { didSet { needsDisplay = true } }
    var timecode = "" { didSet { needsDisplay = true } }
    var capturedImage: NSImage? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        imagePosition = .noImage
        setAccessibilityLabel("Open captured frame".localized)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.52
        layer?.shadowOffset = CGSize(width: 0, height: -7)
        layer?.shadowRadius = 13
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let content = NSRect(x: bounds.maxX - contentWidth, y: 0,
                             width: contentWidth, height: bounds.height)
        NSGraphicsContext.saveGraphicsState()
        let cornerRadius = content.height * 0.12
        NSBezierPath(roundedRect: content, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
        NSColor(srgbRed: 26 / 255, green: 28 / 255, blue: 33 / 255, alpha: 1).setFill()
        NSBezierPath(rect: content).fill()
        if let image = capturedImage, image.size.width > 0, image.size.height > 0 {
            let sourceAspect = image.size.width / image.size.height
            let targetAspect = content.width / max(1, content.height)
            let source: NSRect
            if sourceAspect > targetAspect {
                let width = image.size.height * targetAspect
                source = NSRect(x: (image.size.width - width) / 2, y: 0,
                                width: width, height: image.size.height)
            } else {
                let height = image.size.width / targetAspect
                source = NSRect(x: 0, y: (image.size.height - height) / 2,
                                width: image.size.width, height: height)
            }
            image.draw(in: content, from: source, operation: .sourceOver, fraction: 1)
        }
        let shade = NSRect(x: content.minX, y: content.minY,
                           width: content.width, height: min(35, content.height * 0.28))
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(rect: shade).fill()
        let fontSize = max(8, min(20, content.height * 0.16))
        let label = NSAttributedString(string: timecode, attributes: [
            .font: PanelStyle.inspectFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        label.draw(at: NSPoint(x: content.minX + max(5, content.width * 0.055),
                               y: shade.midY - label.size().height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Small screenshot acknowledgement: a quiet white shutter flash instead of
/// a large modal notification, paired with macOS's familiar Grab sound.
private final class CaptureFeedbackView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.cornerRadius = 10
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func flash() {
        alphaValue = 0
        isHidden = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.06
            animator().alphaValue = 1
        }) { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.24
                self?.animator().alphaValue = 0
            }) { self?.isHidden = true }
        }
    }
}
