import AppKit
import AVFoundation
import AVKit
import Network
import WebKit

/// Figma Shizuka `08 · Video Inspect` / `27 · Video Compare`, on Image
/// Inspect's chrome: the 44 pt titlebar, the stage, a 28 pt transport row 24 pt
/// below the stage and 16 pt above the 92 pt bottom bar (file info, filmstrip,
/// position). Values are top-origin Figma points converted to AppKit frames.
struct VideoInspectChromeLayout {
    static let filmstripBaseSize: CGFloat = InspectLayout.thumbSize
    static let filmstripBaseGap: CGFloat = InspectLayout.thumbGap
    static let transportHeight: CGFloat = 28
    /// Stage → transport, and transport → bottom bar.
    static let transportTopGap: CGFloat = 24
    static let transportBottomGap: CGFloat = 16
    /// Compare panes: 16 pt apart, the caption 16 pt below each pane.
    static let compareGap: CGFloat = 16
    static let captionGap: CGFloat = 16
    static let stageTopMargin: CGFloat = 28
    static let stageSideMargin: CGFloat = 44
    /// Toasts clear the transport row and the bottom bar.
    static let toastInset = InspectLayout.bottomBarHeight + transportBottomGap + transportHeight + PanelStyle.Space.m
    let stage: NSRect
    let transport: NSRect
    let filmstrip: NSRect
    let capture: NSRect

    init(size: NSSize, videoCount: Int) {
        let barHeight = InspectLayout.bottomBarHeight
        transport = NSRect(x: 0, y: barHeight + Self.transportBottomGap,
                           width: size.width, height: Self.transportHeight)
        let bandBottom = transport.maxY + Self.transportTopGap
        let bandTop = size.height - InspectLayout.titlebarHeight
        let band = max(0, bandTop - bandBottom)
        let top = min(Self.stageTopMargin, max(PanelStyle.Space.m, floor(band * 0.05)))
        let side = min(Self.stageSideMargin, max(PanelStyle.Space.l, floor(size.width * 0.04)))
        stage = NSRect(x: side, y: bandBottom, width: max(0, size.width - side * 2), height: max(0, band - top))
        // Up to eight tiles show in full; longer lists show eight and a half
        // and scroll, as in Image Inspect.
        let count = CGFloat(max(1, videoCount))
        let tile = Self.filmstripBaseSize
        let gap = Self.filmstripBaseGap
        let visibleWidth = count <= 8 ? count * tile + (count - 1) * gap : 8.5 * tile + 8 * gap
        let infoRoom = min(240, max(120, size.width * 0.22))
        let stripWidth = max(tile, min(visibleWidth, size.width - infoRoom * 2))
        filmstrip = NSRect(x: ((size.width - stripWidth) / 2).rounded(), y: InspectLayout.filmstripBottom,
                           width: stripWidth, height: tile)
        capture = NSRect(x: max(0, stage.maxX - 220), y: stage.minY, width: 220, height: 125)
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
    private let trialBadge = BillingTrialBadge()
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
    private lazy var closeTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), target: self, action: #selector(closeTapped))
    private lazy var minimizeTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), target: self, action: #selector(minimizeTapped))
    private lazy var zoomTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), target: self, action: #selector(zoomTapped))
    private let focusButton = InspectToolbarButton(symbol: "play.rectangle", tooltip: "Focus".localized)
    private let compareButton = InspectToolbarButton(symbol: "rectangle.split.2x1", tooltip: "Compare".localized)
    private let revealButton = InspectToolbarButton(symbol: "folder", tooltip: "Reveal in Finder".localized)
    private let moreButton = InspectToolbarButton(symbol: "ellipsis", tooltip: "More".localized)
    private let captureButton = InspectToolbarButton(symbol: "camera", tooltip: "Capture frame".localized)
    private let replayButton = InspectToolbarButton(symbol: "arrow.counterclockwise", tooltip: "Replay".localized)
    private let pinButton = InspectToolbarButton(symbol: "pin", tooltip: "Pin on Top".localized)
    private let widgetMarketButton = InspectToolbarButton(symbol: "square.grid.2x2", tooltip: "Widget Market".localized)
    private let infoButton = InspectToolbarButton(symbol: "info.circle", tooltip: "Video information".localized)
    private var isPinned = false
    /// The transport row: play, time, scrubber, duration and Capture frame.
    private let playbackBar = VideoPlaybackBar()
    private lazy var captureFrameButton = InspectDialogButton.make("Capture frame".localized, primary: false,
                                                                    target: self, action: #selector(captureTapped))
    private let bottomBar = InspectBottomBar()
    private let compareCaptions = [VideoCompareCaption(), VideoCompareCaption()]
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
    private let runningStripShade = VideoNonHitTestingView()
    private let runningVideoChip = TaskRunningChip()
    private let copyResultURLButton = WidgetResultURLButton()
    private let toastWindow = InspectToastWindow()
    /// Fired with the temp-file URL of a captured frame; AppDelegate routes it
    /// into the image inspect window.
    var onCaptureFrame: ((URL) -> Void)?
    /// Fired with the saved file once a capture from the editor is written.
    var onCaptured: ((URL) -> Void)?
    /// The capture overlay while it is open; playback stays paused behind it.
    private var captureEditor: CaptureEditorView?
    private var resumeAfterCaptureEditor = false
    private var captureSourceName: String?
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
        appearance = PanelStyle.windowAppearance; backgroundColor = PanelStyle.inspectCanvas
        contentMinSize = NSSize(width: 560, height: 488)
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
           captureEditor == nil,
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
        root.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.contrast.withAlphaComponent(0.22))
        root.layer?.masksToBounds = true
        canvas.acceptsExtension = { ext in
            MediaDropCanvasView.videoExtensions.contains(ext) ||
            MediaDropCanvasView.imageExtensions.contains(ext)
        }
        canvas.acceptsImageData = true
        canvas.onDrop = { [weak self] url, point in
            self?.handleDroppedResource(url: url, at: point)
        }
        // MARK: Titlebar — 44 pt drag region with the window controls on the left.
        identityBar.addSubview(trialBadge)
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
        infoButton.target = self; infoButton.action = #selector(infoTapped)
        pinButton.isActive = isPinned
        // Shizuka `mode switch` (Focus, Capture, Compare, Widget Market) centred,
        // `titlebar actions` (Information, More) on the right.
        for button in [focusButton, captureButton, compareButton, widgetMarketButton, infoButton, moreButton] {
            button.usesShizukaStyle = true
            button.updateTooltip(button.toolTip ?? "")
            inspectToolbar.addSubview(button)
        }
        focusButton.setSymbol("play")
        captureButton.setSymbol("camera")
        compareButton.setDesignIcon("ShizukaCompare")
        widgetMarketButton.setDesignIcon("ShizukaGrid")
        infoButton.setDesignIcon("ShizukaInfo")
        moreButton.setDesignIcon("ShizukaMore")
        canvas.addSubview(inspectToolbar)

        // MARK: Transport — Figma `transport` / `shared transport`.
        playButton.target = self; playButton.action = #selector(playTapped)
        playButton.usesShizukaStyle = true
        playButton.updateTooltip("Play".localized)
        timeline.onChange = { [weak self] value in self?.seek(to: value) }
        currentLabel.textColor = InspectInk.text2
        durationLabel.textColor = InspectInk.text3
        durationLabel.alignment = .right
        separatorLabel.isHidden = true
        [playButton, currentLabel, separatorLabel, timeline, durationLabel, captureFrameButton].forEach { playbackBar.addSubview($0) }
        canvas.addSubview(playbackBar)

        // MARK: Bottom bar — file info left, filmstrip centred, position right.
        canvas.addSubview(bottomBar)
        filmstrip.onSelect = { [weak self] index in
            self?.selectVideo(index)
            self?.offerFailureActions(forItemAt: index)
        }; canvas.addSubview(filmstrip)
        compareCaptions.forEach { caption in
            caption.isHidden = true
            canvas.addSubview(caption)
        }
        inspectToolbar.isHidden = false; inspectToolbar.alphaValue = 1
        identityBar.isHidden = false; identityBar.alphaValue = 1
        filmstrip.isHidden = !showsVideoFilmstrip; filmstrip.alphaValue = 1
        // The Shizuka bottom bar replaces the old running scrim behind the strip.
        runningStripShade.wantsLayer = true
        runningStripShade.layer?.backgroundColor = InspectInk.ink0.withAlphaComponent(0.55).cgColor
        runningStripShade.isHidden = true
        canvas.addSubview(runningStripShade, positioned: .below, relativeTo: filmstrip)
        runningVideoChip.showsSparks = false
        runningVideoChip.isHidden = true
        runningVideoChip.setAccessibilityElement(true)
        canvas.addSubview(runningVideoChip, positioned: .above, relativeTo: filmstrip)
        playbackBar.isHidden = false; playbackBar.alphaValue = 1
        toastWindow.bottomInset = VideoInspectChromeLayout.toastInset
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
        let titleHeight = InspectLayout.titlebarHeight
        let titlebar = NSRect(x: 0, y: b.height - titleHeight, width: b.width, height: titleHeight)
        identityBar.frame = titlebar
        inspectToolbar.frame = titlebar
        // Figma traffic lights: 12 pt at x 20 / 40 / 60, 16 pt from the top.
        for (offset, button) in [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].enumerated() {
            button.frame = NSRect(x: 20 + CGFloat(offset) * 20, y: titleHeight - 16 - 12, width: 12, height: 12)
            button.layer?.cornerRadius = 6
        }
        layoutToolbar(width: b.width)

        // Figma `28 · Video Inspect / Info`: a 320 pt panel under the titlebar.
        let infoWidth = infoVisible ? min(320, max(0, b.width - 320)) : 0
        let canvasW = b.width - infoWidth
        infoPanel.frame = NSRect(x: canvasW, y: 0, width: infoWidth, height: max(0, b.height - titleHeight))
        infoPanel.isHidden = !infoVisible
        let geometry = VideoInspectChromeLayout(size: NSSize(width: canvasW, height: b.height),
                                               videoCount: infos.count)
        let stage = geometry.stage
        bottomBar.frame = NSRect(x: 0, y: 0, width: canvasW, height: InspectLayout.bottomBarHeight)
        var transportSpan = stage
        if mode == .compare, activeIndices.count == 2 {
            // Fit each complete video beside the centred seam, leaving room for
            // the captions below. Spare width stays at the outside edges.
            let gap = VideoInspectChromeLayout.compareGap
            let captionRoom = VideoInspectChromeLayout.captionGap + VideoCompareCaption.height
            let panes = NSRect(x: stage.minX, y: stage.minY + captionRoom,
                               width: stage.width, height: max(1, stage.height - captionRoom))
            let maxWidth = max(1, (panes.width - gap) / 2)
            func fittedSize(for slot: Int) -> CGSize {
                guard let index = activeIndices[safe: slot] else {
                    return CGSize(width: maxWidth, height: panes.height)
                }
                let natural = infos[index].dimensions
                    ?? viewports[safe: slot]?.videoSize
                    ?? .zero
                guard natural.width > 0, natural.height > 0 else {
                    return CGSize(width: maxWidth, height: panes.height)
                }
                let fit = min(maxWidth / natural.width, panes.height / natural.height)
                return CGSize(width: natural.width * fit, height: natural.height * fit)
            }
            let left = fittedSize(for: 0)
            let right = fittedSize(for: 1)
            let seam = panes.midX
            viewports[safe: 0]?.frame = NSRect(x: seam - gap / 2 - left.width,
                                                y: panes.midY - left.height / 2,
                                                width: left.width, height: left.height)
            viewports[safe: 1]?.frame = NSRect(x: seam + gap / 2,
                                                y: panes.midY - right.height / 2,
                                                width: right.width, height: right.height)
            let shown = activeVideoFrame
            transportSpan = shown.isEmpty ? stage : NSRect(x: shown.minX, y: stage.minY, width: shown.width, height: 0)
        } else {
            var shown = stage
            if let index = activeIndices.first {
                let natural = infos[safe: index]?.dimensions ?? viewports.first?.videoSize ?? .zero
                if natural.width > 0, natural.height > 0, stage.width > 0, stage.height > 0 {
                    let fit = min(stage.width / natural.width, stage.height / natural.height)
                    let size = CGSize(width: natural.width * fit, height: natural.height * fit)
                    shown = NSRect(x: stage.midX - size.width / 2, y: stage.midY - size.height / 2,
                                   width: size.width, height: size.height)
                }
            }
            viewports[safe: 0]?.frame = shown
            viewports[safe: 1]?.frame = .zero
            // The transport lines up with the video, never narrower than 480 pt.
            let width = min(stage.width, max(shown.width, 480))
            transportSpan = NSRect(x: stage.midX - width / 2, y: stage.minY, width: width, height: 0)
        }
        for viewport in viewports {
            let toolbarCenter = titlebar.midY - viewport.frame.minY
            viewport.setWidgetIndicatorCenterY(
                toolbarCenter >= 18 && toolbarCenter <= viewport.bounds.maxY - 18
                    ? toolbarCenter : nil)
        }
        layoutCompareCaptions()
        layoutTransport(NSRect(x: transportSpan.minX, y: geometry.transport.minY,
                               width: transportSpan.width, height: geometry.transport.height))

        filmstrip.frame = filmstrip.isHidden ? .zero : geometry.filmstrip
        bottomBar.infoLimitX = filmstrip.isHidden ? .greatestFiniteMagnitude : geometry.filmstrip.minX - PanelStyle.Space.l
        updateBottomBar()
        runningStripShade.frame = .zero
        if currentRunningTask != nil,
           let placement = TaskRunningPlacement.chip(canvas: NSSize(width: canvasW, height: b.height),
               stripTop: geometry.transport.maxY,
               toolbarBottom: titlebar.minY) {
            runningVideoChip.style = placement.style
            runningVideoChip.frame = placement.frame
            runningVideoChip.isHidden = false
        } else {
            runningVideoChip.isHidden = true
        }
        captureFeedback.frame = activeVideoFrame.isEmpty ? stage : activeVideoFrame
        captureThumbnail.contentWidth = 220
        if !captureThumbnail.isHidden, pendingCaptureURL != nil {
            captureThumbnail.frame = geometry.capture
        }
    }

    /// Figma `mode switch` (28 pt tiles, 2 pt gaps, centred, 8 pt from the top)
    /// and `titlebar actions` (4 pt gaps, 20 pt from the right edge), the Widget
    /// result URL action and the trial badge before them — as in Image Inspect.
    private func layoutToolbar(width: CGFloat) {
        let size = InspectLayout.controlSize
        let titleHeight = InspectLayout.titlebarHeight
        let y = titleHeight - 8 - size
        let modeButtons = [focusButton, captureButton, compareButton, widgetMarketButton]
        let modeWidth = CGFloat(modeButtons.count) * size + CGFloat(modeButtons.count - 1) * 2
        var x = ((width - modeWidth) / 2).rounded()
        for button in modeButtons {
            button.frame = NSRect(x: x, y: y, width: size, height: size)
            x += size + 2
        }
        let modeMaxX = x - 2
        var right = width - 20
        for button in [infoButton, moreButton].reversed() {
            button.frame = NSRect(x: right - size, y: y, width: size, height: size)
            right -= size + 4
        }
        if !copyResultURLButton.isHidden {
            copyResultURLButton.frame = NSRect(x: right - size, y: canvas.bounds.height - titleHeight + y,
                                               width: size, height: size)
            right -= size + 4
        }
        right += 4
        let badgeWidth: CGFloat = 146
        let badgeX = right - 12 - badgeWidth
        trialBadge.frame = badgeX >= modeMaxX + 12
            ? NSRect(x: badgeX, y: (titleHeight - 20) / 2, width: badgeWidth, height: 20) : .zero
        trialBadge.refresh()
    }

    /// Figma `transport`: play (28), the current time 16 pt after it, the
    /// scrubber, the duration and — in Focus — Capture frame, 16 pt apart.
    /// The row is 32 pt high so the 32 pt button keeps its full hit area.
    private func layoutTransport(_ row: NSRect) {
        playbackBar.frame = NSRect(x: row.minX, y: row.minY - 2, width: row.width, height: row.height + 4)
        let midY = playbackBar.bounds.midY
        playButton.frame = NSRect(x: 0, y: midY - 14, width: 28, height: 28)
        let currentWidth = max(33, currentLabel.preferredWidth, durationLabel.preferredWidth)
        currentLabel.frame = NSRect(x: 44, y: midY - 7, width: currentWidth, height: 14)
        var trailing = playbackBar.bounds.width
        captureFrameButton.isHidden = mode == .compare
        if !captureFrameButton.isHidden {
            let width = InspectDialogButton.width(captureFrameButton.title)
            captureFrameButton.frame = NSRect(x: trailing - width, y: 0, width: width, height: 32)
            trailing = captureFrameButton.frame.minX - 16
        }
        let durationWidth = max(33, durationLabel.preferredWidth)
        durationLabel.frame = NSRect(x: trailing - durationWidth, y: midY - 7, width: durationWidth, height: 14)
        separatorLabel.frame = .zero
        // The scrubber's knob overhangs its track by half its width.
        let inset = WarmVideoTimeline.knobSize / 2
        let timelineMinX = currentLabel.frame.maxX + 16 - inset
        timeline.frame = NSRect(x: timelineMinX, y: midY - 7,
                                width: max(0, durationLabel.frame.minX - 16 + inset - timelineMinX), height: 14)
    }

    /// Figma `27 · Video Compare`: each pane's caption 16 pt below the video.
    private func layoutCompareCaptions() {
        guard mode == .compare, viewports.count == 2, let pair = compareIndices else {
            compareCaptions.forEach { $0.isHidden = true }
            return
        }
        for (slot, index) in [pair.0, pair.1].enumerated() {
            let caption = compareCaptions[slot]
            guard let info = infos[safe: index], let viewport = viewports[safe: slot],
                  !viewport.frame.isEmpty else {
                caption.isHidden = true
                continue
            }
            let height = VideoCompareCaption.height
            caption.frame = NSRect(x: viewport.frame.minX,
                                   y: viewport.frame.minY - VideoInspectChromeLayout.captionGap - height,
                                   width: viewport.frame.width, height: height)
            var meta: [String] = []
            if let size = info.dimensions { meta.append("\(Int(size.width)) × \(Int(size.height))") }
            let metadata = videoMetadata[safe: index] ?? nil
            if let codec = metadata?.videoCodec { meta.append(codec) }
            if let bitrate = metadata?.videoBitrate, bitrate > 0 {
                meta.append(bitrate >= 1_000_000
                    ? String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
                    : String(format: "%.0f kbps", Double(bitrate) / 1_000))
            }
            caption.configure(letter: slot == 0 ? "A" : "B", name: info.filename,
                              soundState: (viewport.isMuted ? "Muted" : "Sound on").localized,
                              meta: meta.joined(separator: " · "))
            caption.isHidden = false
        }
    }

    /// Figma `file info` and `position` in Focus; Compare names each pane instead.
    private func updateBottomBar() {
        guard mode == .focus, let info = infos[safe: focusedIndex] else {
            bottomBar.showSingle(name: "", meta: "", zoom: "", position: nil)
            return
        }
        var parts: [String] = []
        if let size = info.dimensions { parts.append("\(Int(size.width)) × \(Int(size.height))") }
        if let codec = videoMetadata[safe: focusedIndex].flatMap({ $0?.videoCodec }) { parts.append(codec) }
        if let duration = durations[safe: focusedIndex], duration > 0 { parts.append(Self.formatTime(duration)) }
        bottomBar.showSingle(name: info.filename, meta: parts.joined(separator: "   "), zoom: "",
                             position: infos.count > 1 ? "\(focusedIndex + 1) / \(infos.count)" : nil)
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
        canvas.addSubview(bottomBar, positioned: .above, relativeTo: nil)
        compareCaptions.forEach { canvas.addSubview($0, positioned: .above, relativeTo: nil) }
        canvas.addSubview(playbackBar, positioned: .above, relativeTo: nil)
        canvas.addSubview(runningStripShade, positioned: .above, relativeTo: nil)
        canvas.addSubview(filmstrip, positioned: .above, relativeTo: nil)
        canvas.addSubview(runningVideoChip, positioned: .above, relativeTo: nil)
        canvas.addSubview(infoPanel, positioned: .above, relativeTo: nil)
        canvas.addSubview(inspectToolbar, positioned: .above, relativeTo: nil)
        canvas.addSubview(captureFeedback, positioned: .above, relativeTo: nil)
        canvas.addSubview(captureThumbnail, positioned: .above, relativeTo: nil)
        canvas.addSubview(copyResultURLButton, positioned: .above, relativeTo: nil)
        focusButton.isEnabled = true
        compareButton.isEnabled = infos.count > 1
        focusButton.isActive = mode == .focus
        compareButton.isActive = mode == .compare
        infoButton.isActive = infoVisible
        revealButton.isEnabled = activeIndices.contains { infos[$0].isLocal }
        filmstrip.isHidden = !showsVideoFilmstrip
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
            guard let size, size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else { return nil }
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
        // Metadata can arrive while the user is resizing. Keep their chosen
        // frame rather than issuing a second setFrame inside AppKit's drag loop.
        guard !inLiveResize else { return }
        fittedVideoSignature = signature

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
        let maximum = NSSize(width: visible.width * 0.96, height: visible.height * 0.96)
        contentMinSize = NSSize(width: min(560, maximum.width), height: min(488, maximum.height))
        let contentSize = ScreenManager.mediaWindowSize(
            preferred: preferredSize, minimum: contentMinSize, maximum: maximum)
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
            playButton.setSymbol(isPlaying ? "pause" : "play")
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
        BillingManager.shared.trackTrialActivity("compare")
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
        // Figma `21 · More menu`: the menu drops 6 pt below the ⋯ button and
        // right-aligns with it, as in Image Inspect.
        let buttonRect = moreButton.convert(moreButton.bounds, to: nil)
        let screenPoint = convertToScreen(NSRect(origin: NSPoint(x: buttonRect.maxX, y: buttonRect.minY),
                                                 size: .zero)).origin
        panel.presentBelowToolbar(at: screenPoint, gap: 6)
    }
    @objc private func infoTapped() {
        infoVisible.toggle()
        infoButton.isActive = infoVisible
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
    /// Hands the frozen frame to the capture editor. Playback stays paused
    /// until the editor closes, then resumes if it was playing.
    private func completeCapture(image: NSImage?, at time: Double, resumePlayback: Bool) {
        guard captureEditor == nil, let image, let frozen = CaptureFreeze.frame(image) else {
            if resumePlayback { resumePlaybackAfterCapture() }
            return
        }
        resumeAfterCaptureEditor = resumePlayback
        captureSourceName = infos[safe: activeIndices[safe: mode == .compare ? activeCompareSlot : 0] ?? 0]?.filename
        // Open over the video exactly where it plays (flip to top-left coordinates).
        let video = activeVideoFrame
        let shown: CGRect? = video.isEmpty ? nil
            : CGRect(x: video.minX, y: canvas.bounds.height - video.maxY, width: video.width, height: video.height)
        let editor = CaptureEditorView(image: frozen, displayRect: shown)
        editor.frame = canvas.bounds
        editor.onCancel = { [weak self] in self?.endCaptureEditor() }
        editor.onCapture = { [weak self] cropped in self?.finishCaptureEditor(cropped) }
        canvas.addSubview(editor)
        captureEditor = editor
        makeFirstResponder(editor)
    }
    private func resumePlaybackAfterCapture() {
        viewports.forEach { $0.play() }
        isPlaying = true
        updateTimeline()
    }
    private func endCaptureEditor() {
        guard let editor = captureEditor else { return }
        captureEditor = nil
        editor.removeFromSuperview()
        makeFirstResponder(canvas)
        if resumeAfterCaptureEditor { resumePlaybackAfterCapture() }
        resumeAfterCaptureEditor = false
    }
    private func finishCaptureEditor(_ image: CGImage) {
        let name = captureSourceName
        endCaptureEditor()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = CaptureOutput.save(image, sourceName: name)
            DispatchQueue.main.async {
                guard let self else { return }
                if let url { self.onCaptured?(url) }
                else { self.toastWindow.show(message: "Could not save capture".localized, kind: .error, over: self) }
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
        // The capture editor lays the composite over both panes, so the seam in
        // the image must match the on-screen seam, scaled to the frame's pixels.
        let paneFrames = viewports.map(\.frame).sorted { $0.minX < $1.minX }
        let screenGap = paneFrames.count > 1 ? max(0, paneFrames[1].minX - paneFrames[0].maxX) : 0
        let screenHeight = paneFrames.first?.height ?? 0
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
            let height = frames.map(\.size.height).max() ?? 1
            let gap = screenHeight > 0 && screenGap > 0 ? (screenGap * height / screenHeight).rounded() : 2
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
                                          showsDisclosure: true,
                                          action: { [weak self] in self?.widgetMarketTapped() })
        var widgetEntries: [ActionMenuEntry] = widgets.compactMap { widget in
            let commands = widget.localizedCommands.filter { $0.inputTypes.contains("video") }
            guard !commands.isEmpty else { return nil }
            func entry(_ command: WidgetCommand) -> ActionMenuEntry {
                let currentIndex = activeIndices[safe: mode == .compare ? activeCompareSlot : 0]
                let duplicate = currentIndex.flatMap { infos[safe: $0] }.map { info in
                    WidgetTaskManager.shared.activeRecords(for: info.url).contains {
                        $0.widgetID == widget.id && $0.commandID == command.id
                    }
                } ?? false
                return ActionMenuEntry(title: commands.count == 1 ? widget.displayName : command.name,
                                       creditCost: widget.taskCreditCost, enabled: !duplicate,
                                       action: { [weak self] in self?.runWidget(widget: widget, command: command) })
            }
            if commands.count == 1 { return entry(commands[0]) }
            return ActionMenuEntry(title: widget.displayName, creditCost: widget.taskCreditCost, submenu: commands.map(entry))
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

    /// A red filmstrip tile explains itself when clicked: reason plus Retry / Dismiss.
    private func offerFailureActions(forItemAt index: Int) {
        guard let info = infos[safe: index],
              let record = WidgetTaskManager.shared.latestRecord(for: info.url),
              record.phase.isFailure,
              let tile = filmstrip.screenFrame(ofItemAt: index) else { return }
        let reason = (record.errorMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = reason.isEmpty ? "The task stopped without reporting a reason.".localized
                                   : (reason.count > 60 ? String(reason.prefix(60)) + "…" : reason)
        let id = record.id
        let panel = ActionMenuPanel(entries: [
            ActionMenuEntry(title: "\(record.commandName) · \("Failed".localized)", enabled: false),
            ActionMenuEntry(title: shown, enabled: false),
            .separator(),
            ActionMenuEntry(title: "Retry".localized, action: { WidgetTaskManager.shared.retry(id) }),
            ActionMenuEntry(title: "Dismiss".localized, action: { WidgetTaskManager.shared.remove(id) })
        ])
        actionsPanel?.dismissChain()
        actionsPanel = panel
        panel.present(at: NSPoint(x: tile.minX, y: tile.maxY + 8 + panel.frame.height))
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
        layoutCompareCaptions()
    }

    private func runWidget(widget: WidgetManifest, command: WidgetCommand) {
        guard let index = activeIndices[safe: mode == .compare ? activeCompareSlot : 0],
              infos.indices.contains(index) else { return }
        let info = infos[index]
        guard BillingCoordinator.shared.requireWidgetSignIn(over: self, freeWidget: widget.taskCreditCost == 0, completion: { [weak self] in
            guard let self,
                  let currentIndex = self.activeIndices[safe: self.mode == .compare ? self.activeCompareSlot : 0],
                  self.infos[safe: currentIndex]?.url == info.url else { return }
            self.runWidget(widget: widget, command: command)
        }) else { return }
        let capabilities = command.inputCapabilities
        guard capabilities.needsVideoDialog else {
            _ = WidgetTaskManager.shared.start(widget: widget, command: command, media: info, over: self)
            return
        }
        widgetInputPanel?.close()
        let panel = WidgetVideoInputPanel(widgetName: widget.displayName, sourceURL: info.url,
                                          capabilities: capabilities,
                                          costText: widget.taskCreditCost == 0 ? "Free of charge".localized : widget.creditCostLabel)
        panel.onSubmit = { [weak self] input in
            guard let self, let first = input.mediaURLs.first else { return }
            let media = MediaInfo(url: first, isLocal: first.isFileURL, kind: .video)
            _ = WidgetTaskManager.shared.start(widget: widget, command: command,
                                               media: media, input: input, over: self)
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

    private var currentRunningTask: WidgetTaskRecord? {
        guard mode == .focus, let info = infos[safe: focusedIndex] else { return nil }
        return WidgetTaskManager.shared.activeRecords(for: info.url).first
    }

    private var showsVideoFilmstrip: Bool {
        infos.count > 1 || infos.contains { !WidgetTaskManager.shared.activeRecords(for: $0.url).isEmpty }
    }

    private func updateWidgetTaskIndicators() {
        for viewport in viewports {
            guard let info = infos[safe: viewport.index] else { continue }
            viewport.setWidgetProcessing(WidgetTaskManager.shared.activeRecords(for: info.url).first)
        }
        filmstrip.isHidden = !showsVideoFilmstrip
        runningStripShade.isHidden = !infos.contains { !WidgetTaskManager.shared.activeRecords(for: $0.url).isEmpty }
        if let task = currentRunningTask {
            runningVideoChip.showRunning(detail: task.commandName)
            runningVideoChip.setAccessibilityLabel("\(task.commandName), \("Task running".localized)")
        }
        filmstrip.updateTaskStates(infos: infos, generatedResultPaths: generatedResultPaths)
        copyResultURLButton.isHidden = currentWidgetResultRecord == nil
        layoutContent()
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
                    if let url = URL(string: storedURL), !GlanceAPIHosts.contains(url.host ?? "") {
                        self.copyWidgetResultURLToPasteboard(storedURL)
                    } else {
                        self.toastWindow.show(message: "Could not refresh result URL".localized, kind: .error, over: self)
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
