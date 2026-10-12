import AppKit
import AVFoundation
import AVKit
import Network
import WebKit

/// Figma 110:50 — Video Inspect v4 / Focus / Portrait. All values are logical
/// points. Convert the top-origin reference into AppKit's bottom-origin frames.
/// The video filmstrip follows Image Inspection's smaller sizing per user request.
struct VideoInspectChromeLayout {
    static let filmstripBaseSize: CGFloat = 96 * 0.8 * 0.8
    static let filmstripBaseGap: CGFloat = 8
    let toolbar: NSRect
    let playback: NSRect
    let timeline: NSRect
    let currentTime: NSRect
    let separator: NSRect
    let duration: NSRect
    let filmstrip: NSRect
    let capture: NSRect

    init(size: NSSize, videoCount: Int) {
        func fromTop(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
            NSRect(x: x, y: size.height - y - height, width: width, height: height)
        }
        toolbar = fromTop((size.width - 274) / 2, size.width < 520 ? 56 : 24, 274, 54)
        let barWidth = min(1306, size.width - 48)
        playback = fromTop((size.width - barWidth) / 2, size.height - 88, barWidth, 64)
        // These four frames are local to the 64pt playback bar.
        timeline = NSRect(x: 70, y: 20, width: barWidth - 212, height: 24)
        currentTime = NSRect(x: barWidth - 126, y: 24, width: 42, height: 16)
        separator = NSRect(x: barWidth - 82, y: 24, width: 12, height: 16)
        duration = NSRect(x: barWidth - 68, y: 24, width: 52, height: 16)
        let count = CGFloat(max(1, videoCount))
        // Match ImageInspectWindow's thumbnail scale, including its lower and
        // upper bounds. Keep overflow scrollable instead of squeezing each tile.
        let thumbnailScale = min(max(min(size.width / 1554, size.height / 1012), 0.62), 1.25)
        let tile = Self.filmstripBaseSize * thumbnailScale
        let gap = Self.filmstripBaseGap * thumbnailScale
        let visibleWidth = count <= 8
            ? count * tile + (count - 1) * gap
            : 8.5 * tile + 8 * gap
        let stripWidth = min(visibleWidth, max(1, size.width - 48))
        filmstrip = fromTop((size.width - stripWidth) / 2, size.height - 108 - tile, stripWidth, tile)
        var preview = fromTop(size.width - 244, size.height - 237, 220, 125)
        if videoCount > 1 && preview.intersects(filmstrip) {
            preview.origin.y = filmstrip.maxY + 24
        }
        capture = preview
    }
}

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
    private var displayedPlaybackState: Bool?
    private var playbackEnded = false
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var generation = UUID()
    private var fittedVideoSignature = ""
    private var resizeLayoutScheduled = false
    private var handledWidgetTaskIDs = Set<UUID>()
    private var generatedResultPaths = Set<String>()

    private static let designSize = NSSize(width: 1554, height: 1012)
    private let canvas = MediaDropCanvasView()
    private let inspectToolbar = VideoPlaybackBar()
    private let identityBar = VideoTitlebar()
    private let closeTrafficButton = NSButton()
    private let minimizeTrafficButton = NSButton()
    private let zoomTrafficButton = NSButton()
    private let focusButton = InspectToolbarButton(symbol: "play.rectangle", tooltip: "Focus".localized)
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
    private let currentLabel = VideoTimeLabel("00:00")
    private let separatorLabel = VideoTimeLabel("/")
    private let durationLabel = VideoTimeLabel("00:00")
    private let filmstrip = VideoFilmstripView()
    private let copyResultURLButton = WidgetResultURLButton()
    private let toastWindow = InspectToastWindow()
    /// Fired with the temp-file URL of a captured frame; AppDelegate routes it
    /// into the image inspect window.
    var onCaptureFrame: ((URL) -> Void)?
    /// A dropped image opens in Image Inspect while this video window stays open.
    var onOpenImage: ((MediaInfo) -> Void)?
    /// Themed right-click menu (mute controls), rebuilt per presentation.
    private var actionsPanel: ActionMenuPanel?
    private var widgetInputPanel: WidgetVideoInputPanel?

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
        appearance = NSAppearance(named: .darkAqua); backgroundColor = PanelStyle.inspectCanvas
        contentMinSize = NSSize(width: 320, height: 488)
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true; delegate = self
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
        compareIndices = videos.count > 1 ? (0, 1) : nil
        mode = startsInCompare && videos.count > 1 ? .compare : .focus
        handledWidgetTaskIDs = Set(WidgetTaskManager.shared.records.filter { $0.phase == .completed }.map(\.id))
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(widgetTasksDidChange),
                                               name: WidgetTaskManager.didChange, object: nil)
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
    func windowDidResize(_ notification: Notification) {
        // AppKit is still updating the window's display region during live
        // resize. Lay out video views on the next main-loop turn instead of
        // invalidating their layers inside that cycle.
        guard !resizeLayoutScheduled else { return }
        resizeLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeLayoutScheduled = false
            self.layoutContent()
        }
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
            playTapped()
            return
        }
        if (event.type == .scrollWheel || event.type == .magnify),
           !filmstrip.isHidden, filmstrip.alphaValue >= 0.05,
           filmstrip.frame.contains(canvas.convert(event.locationInWindow, from: nil)) {
            if event.type == .scrollWheel { filmstrip.scrollWheel(with: event) }
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
        guard attachedSheet == nil else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }
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
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(NSColor.white.withAlphaComponent(0.22))
        root.layer?.masksToBounds = true
        canvas.acceptsExtension = { ext in
            MediaDropCanvasView.videoExtensions.contains(ext) ||
            MediaDropCanvasView.imageExtensions.contains(ext)
        }
        canvas.acceptsImageData = true
        canvas.onDrop = { [weak self] url, point in
            self?.handleDroppedResource(url: url, at: point)
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
        for button in [captureButton, focusButton, compareButton,
                       widgetMarketButton, moreButton] {
            button.usesFigmaStyle = true
            button.isBorderlessFigmaTile = true
            button.updateTooltip(button.toolTip ?? "")
            button.layer?.cornerRadius = 9
            inspectToolbar.addSubview(button)
        }
        captureButton.setDesignIcon("VideoInspectCapture")
        focusButton.setDesignIcon("VideoInspectFocus")
        moreButton.setDesignIcon("VideoInspectMore")
        compareButton.setDesignIcon("ToolbarCompare")
        widgetMarketButton.setDesignIcon("ToolbarGrid")
        canvas.addSubview(inspectToolbar)
        playButton.target = self; playButton.action = #selector(playTapped)
        playButton.usesFigmaStyle = true
        playButton.isBorderlessFigmaTile = true
        playButton.updateTooltip("Play".localized)
        playButton.contentTintColor = PanelStyle.accent
        timeline.onChange = { [weak self] value in self?.seek(to: value) }
        playButton.isActive = true
        [playButton, timeline, currentLabel, separatorLabel, durationLabel].forEach { playbackBar.addSubview($0) }
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
        copyResultURLButton.isHidden = true
        copyResultURLButton.onPress = { [weak self] in self?.copyWidgetResultURL() }
        canvas.addSubview(copyResultURLButton, positioned: .above, relativeTo: nil)
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
        canvas.layer?.cornerRadius = 16
        canvas.layer?.borderWidth = 1
        identityBar.frame = NSRect(x: 0, y: b.height - 44, width: b.width, height: 44)
        for (offset, button) in [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].enumerated() {
            // Figma's 12pt traffic lights sit at top 18 inside its 16pt group.
            button.frame = NSRect(x: 20 + CGFloat(offset) * 26, y: 14, width: 12, height: 12)
        }
        let infoWidth = infoVisible ? min(434, max(0, b.width - 320)) : 0
        let canvasW = b.width - infoWidth
        let geometry = VideoInspectChromeLayout(size: NSSize(width: canvasW, height: b.height),
                                               videoCount: infos.count)
        inspectToolbar.frame = geometry.toolbar
        copyResultURLButton.frame = NSRect(x: max(8, canvasW - 24 - 34),
                                           y: geometry.toolbar.midY - 17,
                                           width: 34, height: 34)
        func place(_ button: InspectToolbarButton, x: CGFloat) {
            button.frame = NSRect(x: x, y: 8, width: 38, height: 38)
            button.layer?.cornerRadius = 9
            button.layer?.borderWidth = 0
            button.setSymbolPointSize(18)
        }
        place(captureButton, x: 14)
        place(focusButton, x: 66)
        place(compareButton, x: 118)
        place(widgetMarketButton, x: 170)
        place(moreButton, x: 222)

        let videoRect = NSRect(x: 0, y: 0, width: canvasW, height: b.height)
        infoPanel.frame = NSRect(x: canvasW, y: 0, width: infoWidth, height: b.height)
        infoPanel.isHidden = !infoVisible
        if mode == .compare, activeIndices.count == 2 {
            // Fit each complete video, then place the visible images beside
            // each other. Equal half-window viewports put a large empty band
            // between two portrait videos even though their pane gap is 2pt.
            let gap: CGFloat = 2
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
        for viewport in viewports {
            let toolbarCenter = geometry.toolbar.midY - viewport.frame.minY
            viewport.setWidgetIndicatorCenterY(
                toolbarCenter >= 18 && toolbarCenter <= viewport.bounds.maxY - 18
                    ? toolbarCenter : nil)
        }

        playbackBar.frame = geometry.playback
        playButton.frame = NSRect(x: 16, y: 13, width: 38, height: 38)
        playButton.layer?.cornerRadius = 9
        playButton.setSymbolPointSize(18)
        timeline.frame = geometry.timeline
        currentLabel.frame = geometry.currentTime
        separatorLabel.frame = geometry.separator
        durationLabel.frame = geometry.duration
        filmstrip.frame = geometry.filmstrip
        captureFeedback.frame = videoRect
        captureThumbnail.contentWidth = 220
        if !captureThumbnail.isHidden, pendingCaptureURL != nil {
            captureThumbnail.frame = geometry.capture
        }
    }

    private func render() {
        generation = UUID(); frameCaptureGeneration = UUID(); shouldResumeAfterCapture = false
        playbackEnded = false
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
            viewport.onWebMPosterReady = { [weak self] image in
                guard needsWebMThumbnail else { return }
                needsWebMThumbnail = false
                self?.filmstrip.setThumbnail(image, at: index)
            }
            viewport.onWebMFrameReady = { [weak self, weak viewport] in
                // Let WebKit paint its first frame before requesting a
                // thumbnail. The local poster normally supplies it sooner.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak viewport] in
                    guard needsWebMThumbnail else { return }
                    needsWebMThumbnail = false
                    viewport?.captureWebMThumbnail { [weak self] image in
                        guard let image else { return }
                        self?.filmstrip.setThumbnail(image, at: index)
                    }
                }
            }
            viewport.onTimeUpdate = { [weak self, weak viewport] time in
                guard let self, self.isPlaying, self.viewports.first === viewport else { return }
                self.currentTime = min(max(0, time), self.maximumDuration)
                self.updateTimeline()
            }
            viewport.onEnded = { [weak self] in self?.playbackDidEnd() }
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
        canvas.addSubview(copyResultURLButton, positioned: .above, relativeTo: nil)
        focusButton.isEnabled = true
        compareButton.isEnabled = infos.count > 1
        focusButton.isActive = mode == .focus
        compareButton.isActive = mode == .compare
        revealButton.isEnabled = activeIndices.contains { infos[$0].isLocal }
        filmstrip.isHidden = infos.count < 2
        filmstrip.configure(infos: infos, selectedIndex: focusedIndex,
                            compareIndices: mode == .compare ? compareIndices : nil,
                            generatedResultPaths: generatedResultPaths)
        copyResultURLButton.isHidden = currentWidgetResultRecord == nil
        updateWidgetTaskIndicators()
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
        // Metadata can arrive while the user is resizing. Keep their chosen
        // frame rather than issuing a second setFrame inside AppKit's drag loop.
        guard !inLiveResize else { return }

        let aspect = targetSize.width / targetSize.height
        // Focus fits media inside the reference window; window proportions do
        // not follow the source video's aspect ratio (Portrait is 560 × 900).
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = ScreenManager.shared.screenForMouseLocation(center)
                ?? self.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let preferredSize = mode == .focus
            ? (aspect < 1 ? NSSize(width: 560, height: 900) : NSSize(width: 1120, height: 700))
            : targetSize
        let downscale = min(1, visible.width * 0.96 / preferredSize.width,
                            visible.height * 0.96 / preferredSize.height)
        let contentSize = NSSize(width: max(contentMinSize.width, preferredSize.width * downscale),
                                 height: max(contentMinSize.height, preferredSize.height * downscale))
        let frameSize = frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        var origin = NSPoint(x: center.x - frameSize.width / 2,
                             y: center.y - frameSize.height / 2)
        origin.x = max(visible.minX, min(origin.x, visible.maxX - frameSize.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - frameSize.height))
        setFrame(ScreenManager.shared.clampedToVisible(NSRect(origin: origin, size: frameSize)),
                 display: true, animate: false)
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
    private var maximumDuration: Double { activeIndices.compactMap { durations[safe: $0] }.max() ?? 0 }
    private func installObserver() {
        if endObserver == nil {
            // Filter against the current items so cached-source replacements
            // and either native player in Compare still report completion.
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
                guard let self, let item = notification.object as? AVPlayerItem,
                      self.viewports.contains(where: { $0.player?.currentItem === item }) else { return }
                self.playbackDidEnd()
            }
        }
        guard timeObserver == nil, let player = viewports.first?.player else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600), queue: .main) { [weak self] time in guard let self, self.isPlaying else { return }; self.currentTime = min(max(0, time.seconds), self.maximumDuration); self.updateTimeline() }
    }
    private func updateTimeline() {
        timeline.maximum = maximumDuration
        timeline.value = currentTime
        currentLabel.stringValue = Self.formatTime(currentTime)
        durationLabel.stringValue = Self.formatTime(maximumDuration)
        if displayedPlaybackState != isPlaying {
            if isPlaying { playButton.setDesignIcon("VideoInspectPause") }
            else { playButton.setSymbol("play.fill") }
            playButton.updateTooltip(isPlaying ? "Pause".localized : "Play".localized)
            displayedPlaybackState = isPlaying
        }
    }
    private var shouldReplay: Bool {
        playbackEnded || viewports.contains { $0.hasReachedEnd }
    }
    @objc private func playTapped() {
        if isPlaying && !shouldReplay { pausePlayback() }
        else { playPlayback() }
    }
    private func playbackDidEnd() {
        playbackEnded = true
        pausePlayback()
    }
    private func playPlayback() {
        let token = generation
        // Replay all visible videos together; ordinary pauses resume in place.
        seek(to: shouldReplay ? 0 : currentTime) { [weak self] in
            guard let self, self.generation == token else { return }
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
        playbackEnded = false
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
    @objc private func compareTapped() {
        guard infos.count > 1 else { return }
        // A Widget result (or its source) compares as (original, result), so A
        // is the original regardless of item order.
        let storedContainsFocused = compareIndices.map { $0.0 == focusedIndex || $0.1 == focusedIndex } ?? false
        if !storedContainsFocused, let widgetPair = widgetComparePair(focused: focusedIndex) {
            compareIndices = widgetPair
        }
        if compareIndices == nil { compareIndices = (focusedIndex, focusedIndex == 0 ? 1 : 0) }
        mode = .compare; pausePlayback(); render()
    }

    private func widgetComparePair(focused: Int) -> (Int, Int)? {
        guard infos.indices.contains(focused) else { return nil }
        let manager = WidgetTaskManager.shared
        if let source = manager.sourceURL(forResult: infos[focused].url),
           let sourceIndex = infos.indices.first(where: { manager.isSameMedia(infos[$0].url, source) }) {
            return (sourceIndex, focused)
        }
        for output in manager.completedOutputs(for: infos[focused].url) {
            if let resultIndex = infos.indices.first(where: { manager.isSameMedia(infos[$0].url, output) }) {
                return (focused, resultIndex)
            }
        }
        return nil
    }
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
        // Freeze the visible frame. Compare mode also seeks every player to
        // the same master time so its captures stay aligned.
        let playerTime = viewports.first?.currentTime ?? currentTime
        let captureTime = playerTime.isFinite ? max(0, playerTime) : max(0, currentTime)
        shouldResumeAfterCapture = shouldResumeAfterCapture || isPlaying
        let captureGeneration = generation
        frameCaptureGeneration = UUID()
        let frameCaptureToken = frameCaptureGeneration
        pausePlayback()
        if mode != .compare {
            finishCapture(at: captureTime, token: frameCaptureToken)
            return
        }
        seek(to: captureTime) { [weak self] in
            guard let self, self.generation == captureGeneration,
                  self.frameCaptureGeneration == frameCaptureToken else { return }
            self.finishCapture(at: captureTime, token: frameCaptureToken)
        }
    }
    private func finishCapture(at time: Double, token: UUID) {
        let sourceToken = generation
        captureCurrentFrame(at: time) { [weak self] image in
            guard let self, self.generation == sourceToken,
                  self.frameCaptureGeneration == token else { return }
            let resumePlayback = self.shouldResumeAfterCapture
            self.shouldResumeAfterCapture = false
            self.completeCapture(image: image, at: time, resumePlayback: resumePlayback)
        }
    }
    private func completeCapture(image: NSImage?, at time: Double, resumePlayback: Bool) {
        if resumePlayback {
            viewports.forEach { $0.play() }
            isPlaying = true
            updateTimeline()
        }
        guard let image else { return }
        NSSound(named: "Grab")?.play()
        captureFeedback.flash()
        // Keep the captured frame ready for the thumbnail's existing Image
        // Inspect handoff. A second capture replaces the pending preview.
        let sourceToken = generation
        let captureToken = frameCaptureGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("GlanceCaptures", isDirectory: true)
            let url = directory.appendingPathComponent("capture-\(UUID().uuidString).png")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try png.write(to: url)
            } catch {
                Logger.error("Video capture write failed: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.async {
                guard let self, self.generation == sourceToken,
                      self.frameCaptureGeneration == captureToken else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                self.showCaptureThumbnail(image: image, time: time, url: url)
            }
        }
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
                DispatchQueue.main.async {
                    captured[offset] = image
                    group.leave()
                }
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
        let marketEntry = ActionMenuEntry(title: "Widget Market…".localized,
                                          action: { [weak self] in self?.widgetMarketTapped() })
        var widgetEntries: [ActionMenuEntry] = widgets.compactMap { widget in
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
        }
        entries.append(.separator())
        if widgetEntries.isEmpty {
            // Nothing installed (or nothing fits this video): keep the Market one click away.
            entries.append(marketEntry)
        } else {
            widgetEntries.append(.separator())
            widgetEntries.append(marketEntry)
            entries.append(ActionMenuEntry(title: "Widgets".localized, submenu: widgetEntries))
        }
        // A running task on the current video can be stopped from the same menu.
        let manager = WidgetTaskManager.shared
        if let currentIndex = activeIndices[safe: mode == .compare ? activeCompareSlot : 0],
           let info = infos[safe: currentIndex] {
            let cancellable = manager.activeRecords(for: info.url).filter(manager.canCancel)
            for record in cancellable {
                entries.append(ActionMenuEntry(title: String(format: "Cancel %@".localized, record.commandName),
                                               action: { WidgetTaskManager.shared.cancel(record.id) }))
            }
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
        let info = infos[index]
        let capabilities = command.inputCapabilities
        guard capabilities.needsVideoDialog else {
            _ = WidgetTaskManager.shared.start(widget: widget, command: command, media: info)
            return
        }
        widgetInputPanel?.close()
        let panel = WidgetVideoInputPanel(widgetName: widget.name, sourceURL: info.url,
                                          capabilities: capabilities)
        panel.onSubmit = { input in
            guard let first = input.mediaURLs.first else { return }
            let media = MediaInfo(url: first, isLocal: first.isFileURL, kind: .video)
            _ = WidgetTaskManager.shared.start(widget: widget, command: command,
                                               media: media, input: input)
        }
        panel.onDismiss = { [weak self, weak panel] in
            if self?.widgetInputPanel === panel { self?.widgetInputPanel = nil }
        }
        widgetInputPanel = panel
        panel.present(over: self)
    }

    @objc private func widgetTasksDidChange() {
        let completed = WidgetTaskManager.shared.records.filter {
            $0.phase == .completed && !handledWidgetTaskIDs.contains($0.id)
        }
        completed.forEach { handledWidgetTaskIDs.insert($0.id) }
        for task in completed.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            guard let source = task.source, let output = task.output,
                  infos.contains(where: { $0.url.absoluteString == source.absoluteString }) else { continue }
            let detected = MediaInfo.from(pathDetector.localKind(for: output.path))
            let unknownResult = detected == nil || detected?.kind == .other
            if detected?.kind == .video ||
                (unknownResult && task.outputTypes?.contains("video") == true) {
                insertWidgetResult(output, after: source)
            } else if detected?.kind == .image ||
                        (unknownResult && task.outputTypes?.contains("image") == true) {
                onOpenImage?(MediaInfo(url: output, isLocal: true, kind: .image))
            }
        }
        updateWidgetTaskIndicators()
    }

    private func insertWidgetResult(_ output: URL, after source: URL) {
        guard let sourceIndex = infos.firstIndex(where: { $0.url.absoluteString == source.absoluteString }) else { return }
        if let existingIndex = infos.firstIndex(where: { $0.url.standardizedFileURL == output.standardizedFileURL }) {
            focusedIndex = existingIndex
        } else {
            let index = sourceIndex + 1
            infos.insert(MediaInfo(url: output, isLocal: true, kind: .video), at: index)
            durations.insert(0, at: index)
            videoMetadata.insert(nil, at: index)
            generatedResultPaths.insert(output.standardizedFileURL.path)
            focusedIndex = index
        }
        mode = .focus
        pausePlayback()
        render()
    }

    private func updateWidgetTaskIndicators() {
        for viewport in viewports {
            guard let info = infos[safe: viewport.index] else { continue }
            viewport.setWidgetProcessing(!WidgetTaskManager.shared.activeRecords(for: info.url).isEmpty)
        }
        filmstrip.updateTaskStates(infos: infos, generatedResultPaths: generatedResultPaths)
        copyResultURLButton.isHidden = currentWidgetResultRecord == nil
    }

    private var currentWidgetResultRecord: WidgetTaskRecord? {
        guard mode == .focus, let info = infos[safe: focusedIndex], info.isLocal,
              WidgetTaskManager.shared.activeRecords(for: info.url).isEmpty,
              let record = WidgetTaskManager.shared.completedRecord(for: info.url),
              record.copyableMediaResultURL != nil else { return nil }
        return record
    }

    private func copyWidgetResultURL() {
        guard let record = currentWidgetResultRecord,
              let storedURL = record.copyableMediaResultURL else { return }
        guard let taskID = record.remoteTaskID else {
            copyWidgetResultURLToPasteboard(storedURL)
            return
        }
        WidgetTaskClient.shared.fetchResultURL(taskID: taskID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.currentWidgetResultRecord?.id == record.id else { return }
                switch result {
                case .success(let url): self.copyWidgetResultURLToPasteboard(url.absoluteString)
                case .failure:
                    if let url = URL(string: storedURL), url.host != "api.glance.mcreator.ai" {
                        self.copyWidgetResultURLToPasteboard(storedURL)
                    } else {
                        self.toastWindow.show(message: "Could not refresh result URL".localized, over: self)
                    }
                }
            }
        }
    }

    private func copyWidgetResultURLToPasteboard(_ url: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(url, forType: .string) {
            toastWindow.show(message: "URL copied ✓".localized, over: self)
        }
    }

    private func handleDroppedVideo(url: URL, at point: NSPoint) {
        let path: DetectedPath = url.isFileURL
            ? .localVideo(url.standardizedFileURL) : .remoteVideo(url)
        HistoryManager.shared.record(selectedText: "", detectedPaths: [path])
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

    private func handleDroppedResource(url: URL, at point: NSPoint) {
        let info: MediaInfo?
        if url.isFileURL {
            info = MediaInfo.from(pathDetector.localKind(for: url.path))
        } else {
            info = pathDetector.detectAll(url.absoluteString)
                .compactMap(MediaInfo.from).first
        }
        guard let info else { return }
        switch info.kind {
        case .image:
            onOpenImage?(info)
        case .video:
            handleDroppedVideo(url: info.url, at: point)
        default:
            break
        }
    }

    /// ⌘V uses the same PathDetector classification as selection activation.
    /// Duplicate URLs focus the existing video; new URLs append and display.
    private func pasteRemoteVideoFromClipboard() -> Bool {
        guard let text = ImageInspectWindow.clipboardText(),
              let info = pathDetector.detectAll(text)
                .compactMap(MediaInfo.from)
                .first(where: { $0.kind == .video && !$0.isLocal }) else { return false }
        HistoryManager.shared.record(selectedText: "", detectedPaths: [.remoteVideo(info.url)])
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
        NotificationCenter.default.removeObserver(self, name: WidgetTaskManager.didChange, object: nil)
        WidgetTaskManager.shared.clearFailed(for: infos.map(\.url))
        removeChildWindow(toastWindow)
        toastWindow.orderOut(nil)
        widgetInputPanel?.close(); widgetInputPanel = nil
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
    private static func formatTime(_ seconds: Double) -> String { let total = max(0, Int(seconds.rounded(.down))); return String(format: "%02d:%02d", total / 60, total % 60) }

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
