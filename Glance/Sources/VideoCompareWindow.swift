import AppKit
import AVFoundation
import AVKit

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
    private var players: [AVPlayer] = []
    private var viewports: [VideoInspectViewport] = []
    private var durations: [Double]
    private var videoMetadata: [VideoTechnicalMetadata?]
    private let pathDetector = PathDetector()
    private var currentTime = 0.0
    private var isPlaying = false
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var generation = UUID()

    private static let designSize = NSSize(width: 1554, height: 1012)
    private let canvas = MediaDropCanvasView()
    private let inspectToolbar = NSView()
    private let identityBar = VideoTitlebar()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let closeTrafficButton = NSButton()
    private let minimizeTrafficButton = NSButton()
    private let zoomTrafficButton = NSButton()
    private let focusButton = InspectToolbarButton(symbol: "photo", tooltip: "Focus".localized)
    private let compareButton = InspectToolbarButton(symbol: "rectangle.split.2x1", tooltip: "Compare".localized)
    private let fitButton = InspectToolbarButton(symbol: "arrow.up.left.and.arrow.down.right", tooltip: "Fit".localized)
    private let revealButton = InspectToolbarButton(symbol: "folder", tooltip: "Reveal in Finder".localized)
    private let infoButton = InspectToolbarButton(symbol: "info.circle", tooltip: "Video information".localized)
    private let captureButton = InspectToolbarButton(symbol: "camera", tooltip: "Capture frame".localized)
    private let replayButton = InspectToolbarButton(symbol: "arrow.counterclockwise", tooltip: "Replay".localized)
    private let pinButton = InspectToolbarButton(symbol: "pin", tooltip: "Pin on Top".localized)
    private let widgetMarketButton = InspectToolbarButton(symbol: "square.grid.2x2", tooltip: "Widget Market".localized)
    private let widgetTasksButton = InspectToolbarButton(symbol: "tray.full", tooltip: "Tasks".localized)
    private var isPinned = false
    private let playbackBar = VideoPlaybackBar()
    private let captureFeedback = CaptureFeedbackView()
    private let infoPanel = VideoInformationView()
    private let statusbar = NSView()
    private let statusLeft = NSTextField(labelWithString: "")
    private let statusCenter = NSTextField(labelWithString: "Space to play or pause".localized)
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
        minSize = NSSize(width: 900, height: 586); contentAspectRatio = Self.designSize
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true; delegate = self
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
        // Video chrome stays persistent, matching the Image Inspect workbench.
        // Hover can change button emphasis but must not hide playback controls.
        super.sendEvent(event)
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
        root.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        root.layer?.masksToBounds = true
        canvas.acceptsExtension = { ext in
            MediaDropCanvasView.videoExtensions.contains(ext)
        }
        canvas.onDrop = { [weak self] url, point in
            self?.handleDroppedVideo(url: url, at: point)
        }
        titleLabel.font = PanelStyle.inspectFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.alignment = .center
        metaLabel.font = PanelStyle.inspectFont(ofSize: 11)
        metaLabel.textColor = PanelStyle.textTertiary
        metaLabel.alignment = .center
        for label in [titleLabel, metaLabel] {
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            identityBar.addSubview(label)
        }
        configureTraffic(closeTrafficButton, color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), tooltip: "Close".localized, action: #selector(closeTapped))
        configureTraffic(minimizeTrafficButton, color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), tooltip: "Minimize".localized, action: #selector(minimizeTapped))
        configureTraffic(zoomTrafficButton, color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), tooltip: "Zoom".localized, action: #selector(zoomTapped))
        [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].forEach(identityBar.addSubview)
        canvas.addSubview(identityBar)
        focusButton.target = self; focusButton.action = #selector(focusTapped)
        compareButton.target = self; compareButton.action = #selector(compareTapped)
        fitButton.target = self; fitButton.action = #selector(fitTapped)
        revealButton.target = self; revealButton.action = #selector(revealTapped)
        infoButton.target = self; infoButton.action = #selector(infoTapped)
        captureButton.target = self; captureButton.action = #selector(captureTapped)
        replayButton.target = self; replayButton.action = #selector(replayTapped)
        pinButton.target = self; pinButton.action = #selector(pinTapped)
        widgetMarketButton.target = self; widgetMarketButton.action = #selector(widgetMarketTapped)
        widgetTasksButton.target = self; widgetTasksButton.action = #selector(widgetTasksTapped)
        pinButton.isActive = isPinned
        inspectToolbar.wantsLayer = true
        inspectToolbar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        inspectToolbar.layer?.borderWidth = 1
        inspectToolbar.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        for button in [captureButton, focusButton, compareButton, fitButton,
                       widgetTasksButton, widgetMarketButton, infoButton] {
            button.usesFigmaStyle = true
            button.updateTooltip(button.toolTip ?? "")
            button.layer?.cornerRadius = 8
            inspectToolbar.addSubview(button)
        }
        canvas.addSubview(inspectToolbar)
        playButton.target = self; playButton.action = #selector(playTapped)
        playButton.usesFigmaStyle = true
        playButton.updateTooltip("Play".localized)
        playButton.isActive = true
        timeline.onChange = { [weak self] value in self?.seek(to: value) }
        for label in [currentLabel, durationLabel] {
            label.font = PanelStyle.inspectFont(ofSize: 12, weight: label === currentLabel ? .medium : .regular)
            label.textColor = label === currentLabel ? PanelStyle.textSecondary : PanelStyle.textTertiary
            label.alignment = .center
        }
        [playButton, timeline, currentLabel, durationLabel].forEach { playbackBar.addSubview($0) }
        canvas.addSubview(playbackBar)
        filmstrip.onSelect = { [weak self] index in self?.selectVideo(index) }; canvas.addSubview(filmstrip)
        // Keep the media chrome visible in the first frame. Video Inspect uses
        // the same persistent workbench hierarchy as Image Inspect; hover only
        // changes emphasis, it does not remove playback controls.
        inspectToolbar.isHidden = false; inspectToolbar.alphaValue = 1
        identityBar.isHidden = false; identityBar.alphaValue = 1
        filmstrip.isHidden = infos.count < 2; filmstrip.alphaValue = 1
        playbackBar.isHidden = false; playbackBar.alphaValue = 1
        infoPanel.autoresizingMask = [.width, .height]
        infoPanel.isHidden = true
        canvas.addSubview(infoPanel)
        statusbar.wantsLayer = true
        statusbar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectStatus)
        statusbar.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        statusbar.layer?.borderWidth = 1
        for label in [statusLeft, statusCenter] {
            label.font = PanelStyle.inspectFont(ofSize: 12)
            label.textColor = PanelStyle.textSecondary
            statusbar.addSubview(label)
        }
        statusCenter.alignment = .center
        canvas.addSubview(statusbar)
        captureFeedback.isHidden = true
        canvas.addSubview(captureFeedback, positioned: .above, relativeTo: nil)
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

        identityBar.frame = NSRect(x: 0, y: b.height - 58 * sy, width: b.width, height: 58 * sy)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 15 * sy, weight: .semibold)
        metaLabel.font = PanelStyle.inspectFont(ofSize: 11 * sy)
        titleLabel.frame = NSRect(x: 0, y: 26 * sy, width: b.width, height: 18 * sy)
        metaLabel.frame = NSRect(x: 0, y: 7 * sy, width: b.width, height: 13 * sy)
        for (offset, button) in [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].enumerated() {
            button.frame = NSRect(x: (24 + CGFloat(offset) * 20) * sx, y: 23 * sy,
                                  width: 12 * sx, height: 12 * sy)
            button.layer?.cornerRadius = 6 * scale
        }

        inspectToolbar.frame = NSRect(x: 0, y: b.height - 128 * sy,
                                      width: b.width, height: 70 * sy)
        inspectToolbar.layer?.borderWidth = max(1, scale)
        func place(_ button: InspectToolbarButton, x: CGFloat) {
            button.frame = NSRect(x: x * sx, y: 18 * sy, width: 38 * sx, height: 38 * sy)
            button.layer?.cornerRadius = 8 * scale
            button.layer?.borderWidth = max(1, scale)
        }
        place(captureButton, x: 40)
        place(focusButton, x: 686)
        place(compareButton, x: 734)
        place(fitButton, x: 782)
        place(widgetTasksButton, x: 1378)
        place(widgetMarketButton, x: 1426)
        place(infoButton, x: 1474)

        let statusH = 37 * sy
        statusbar.frame = NSRect(x: 0, y: 0, width: b.width, height: statusH)
        statusbar.layer?.borderWidth = max(1, scale)
        statusLeft.font = PanelStyle.inspectFont(ofSize: 12 * sy)
        statusCenter.font = PanelStyle.inspectFont(ofSize: 12 * sy)
        statusLeft.frame = NSRect(x: 38 * sx, y: 11 * sy, width: 480 * sx, height: 15 * sy)
        statusCenter.frame = NSRect(x: 0, y: 11 * sy, width: b.width, height: 15 * sy)

        let canvasW = max(0, b.width - (infoVisible ? 434 * sx : 0))
        let videoRect = NSRect(x: 0, y: statusH, width: canvasW, height: 847 * sy)
        infoPanel.frame = NSRect(x: canvasW, y: statusH, width: 434 * sx, height: videoRect.height)
        infoPanel.isHidden = !infoVisible
        if mode == .compare, activeIndices.count == 2 {
            let gap = max(1, scale)
            let half = (videoRect.width - gap) / 2
            viewports[safe: 0]?.frame = NSRect(x: 0, y: videoRect.minY, width: half, height: videoRect.height)
            viewports[safe: 1]?.frame = NSRect(x: half + gap, y: videoRect.minY, width: half, height: videoRect.height)
        } else {
            viewports[safe: 0]?.frame = videoRect
            viewports[safe: 1]?.frame = .zero
        }

        let barWidth = min(1306 * sx, max(0, canvasW - 96 * sx))
        playbackBar.frame = NSRect(x: (canvasW - barWidth) / 2, y: statusH + 61 * sy,
                                   width: barWidth, height: 64 * sy)
        playbackBar.layer?.cornerRadius = 12 * scale
        playbackBar.layer?.borderWidth = max(1, scale)
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
    }

    private func render() {
        generation = UUID(); removeObservers(); viewports.forEach { $0.removeFromSuperview() }; viewports.removeAll(); players.forEach { $0.pause() }; players.removeAll(); isPlaying = false; currentTime = 0
        for index in activeIndices {
            let info = infos[index]
            let player = AVPlayer(url: info.url)
            player.isMuted = true
            // Both compare players should start immediately after the shared
            // exact seek instead of independently waiting for buffering.
            player.automaticallyWaitsToMinimizeStalling = false
            let viewport = VideoInspectViewport(index: index, player: player)
            viewport.dropTarget = canvas
            viewport.onActionMenu = { [weak self] event in
                guard let self, let window = event.window else { return }
                let origin = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
                self.presentMuteMenu(atScreenPoint: origin)
            }
            viewport.onActivate = { [weak self] in
                guard let self else { return }
                self.activeCompareSlot = self.compareIndices?.0 == index ? 0 : 1
                self.updateVideoCompareDimming()
                self.refreshInfoPanel()
            }
            viewport.setCompareDimmed(mode == .compare && activeCompareSlot != (compareIndices?.0 == index ? 0 : 1))
            canvas.addSubview(viewport, positioned: .below, relativeTo: inspectToolbar); players.append(player); viewports.append(viewport)
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
        canvas.addSubview(statusbar, positioned: .above, relativeTo: nil)
        canvas.addSubview(inspectToolbar, positioned: .above, relativeTo: nil)
        canvas.addSubview(captureFeedback, positioned: .above, relativeTo: nil)
        titleLabel.stringValue = "Video Inspect".localized
        metaLabel.stringValue = infos[safe: activeIndices[safe: mode == .compare ? activeCompareSlot : 0] ?? focusedIndex]?.filename ?? ""
        focusButton.isEnabled = true
        compareButton.isEnabled = infos.count > 1
        focusButton.isActive = mode == .focus
        compareButton.isActive = mode == .compare
        revealButton.isEnabled = activeIndices.contains { infos[$0].isLocal }
        infoButton.isActive = infoVisible
        filmstrip.isHidden = infos.count < 2
        filmstrip.configure(infos: infos, selectedIndex: focusedIndex, compareIndices: mode == .compare ? compareIndices : nil)
        refreshInfoPanel()
        updateTimeline(); layoutContent(); loadDurations()
    }

    private func loadDurations() {
        let token = generation
        for (index, info) in infos.enumerated() {
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
                    self.updateTimeline()
                    self.refreshInfoPanel()
                }
            }
        }
        installObserver()
    }
    private var maximumDuration: Double { durations.max() ?? 0 }
    private func installObserver() {
        guard timeObserver == nil, let player = players.first else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600), queue: .main) { [weak self] time in guard let self, self.isPlaying else { return }; self.currentTime = min(max(0, time.seconds), self.maximumDuration); self.updateTimeline() }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in self?.pausePlayback() }
    }
    private func updateTimeline() {
        timeline.maximum = maximumDuration
        timeline.value = currentTime
        currentLabel.stringValue = Self.formatTime(currentTime)
        durationLabel.stringValue = Self.formatTime(maximumDuration)
        playButton.setSymbol(isPlaying ? "pause.fill" : "play.fill")
        let index = activeIndices[safe: mode == .compare ? activeCompareSlot : 0] ?? focusedIndex
        guard infos.indices.contains(index) else { return }
        let info = infos[index]
        var parts: [String] = []
        if let codec = videoMetadata[safe: index]??.videoCodec { parts.append(codec) }
        if let size = info.dimensions { parts.append("\(Int(size.width)) × \(Int(size.height))") }
        if let fps = videoMetadata[safe: index]??.fps { parts.append(String(format: "%g fps", Double(fps))) }
        statusLeft.stringValue = parts.isEmpty ? info.filename : parts.joined(separator: "  •  ")
    }
    @objc private func playTapped() { isPlaying ? pausePlayback() : playPlayback() }
    private func playPlayback() {
        seek(to: currentTime) { [weak self] in
            guard let self else { return }
            // setRate(_:atHostTime:) throws when an AVPlayer has no usable
            // host-time anchor. Exact-seek both first, then start them in this
            // single main-thread turn with buffering waits disabled.
            self.players.forEach { $0.playImmediately(atRate: 1) }
            self.isPlaying = true
            self.updateTimeline()
        }
    }
    private func pausePlayback() { players.forEach { $0.pause() }; isPlaying = false; updateTimeline() }
    private func seek(to time: Double, completion: (() -> Void)? = nil) {
        currentTime = min(max(0, time), maximumDuration); let group = DispatchGroup()
        for (offset, player) in players.enumerated() { let index = activeIndices[safe: offset] ?? focusedIndex; let limit = durations[safe: index] ?? maximumDuration; group.enter(); player.seek(to: CMTime(seconds: min(currentTime, limit), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in group.leave() } }
        updateTimeline(); group.notify(queue: .main) { completion?() }
    }
    @objc private func focusTapped() { mode = .focus; pausePlayback(); render() }
    @objc private func compareTapped() { guard infos.count > 1 else { return }; if compareIndices == nil { compareIndices = (focusedIndex, focusedIndex == 0 ? 1 : 0) }; mode = .compare; pausePlayback(); render() }
    @objc private func fitTapped() { viewports.forEach { $0.fitToView() } }
    @objc private func widgetTasksTapped() { (NSApp.delegate as? AppDelegate)?.openTasks() }
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
        // Freeze and exactly seek every player to the same master time before
        // reading pixels. Generating frames while playback continues returns
        // neighboring keyframes at different moments.
        let playerTime = players.first?.currentTime().seconds ?? currentTime
        let captureTime = playerTime.isFinite ? max(0, playerTime) : max(0, currentTime)
        pausePlayback()
        seek(to: captureTime) { [weak self] in
            self?.finishCapture(at: captureTime)
        }
    }
    private func finishCapture(at time: Double) {
        guard let image = captureCurrentFrame(at: time) else { return }
        NSSound(named: "Grab")?.play()
        captureFeedback.flash()
        // No save panel: hand the frame straight to Image Inspect. Repeated
        // captures append to its filmstrip.
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("capture-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        do {
            try png.write(to: url)
        } catch {
            Logger.error("Video capture write failed: \(error.localizedDescription)")
            return
        }
        // Defer until the capture button's mouse event has finished; otherwise
        // AppKit can re-key the video window after Image Inspect is presented.
        DispatchQueue.main.async { [weak self] in self?.onCaptureFrame?(url) }
    }
    private func captureCurrentFrame(at time: Double) -> NSImage? {
        let frames: [NSImage] = players.enumerated().compactMap { offset, player in
            guard let item = player.currentItem else { return nil }
            let generator = AVAssetImageGenerator(asset: item.asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let index = activeIndices[safe: offset] ?? focusedIndex
            let limit = durations[safe: index] ?? maximumDuration
            let target = CMTime(seconds: min(max(0, time), limit), preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: target, actualTime: nil) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        }
        guard !frames.isEmpty else { return nil }
        if frames.count == 1 { return frames[0] }
        let gap: CGFloat = 2
        let height = frames.map(\.size.height).max() ?? 1
        let width = frames.reduce(0) { $0 + ($1.size.width * height / max(1, $1.size.height)) } + gap
        let output = NSImage(size: NSSize(width: width, height: height))
        output.lockFocus(); NSColor.black.setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: output.size)).fill()
        var x: CGFloat = 0
        for frame in frames {
            let frameWidth = frame.size.width * height / max(1, frame.size.height)
            frame.draw(in: NSRect(x: x, y: 0, width: frameWidth, height: height), from: .zero, operation: .sourceOver, fraction: 1)
            x += frameWidth + gap
        }
        output.unlockFocus(); return output
    }
    private func selectVideo(_ index: Int) { guard infos.indices.contains(index) else { return }; if mode == .compare, let pair = compareIndices { if activeCompareSlot == 0, index != pair.1 { compareIndices = (index, pair.1) } else if activeCompareSlot == 1, index != pair.0 { compareIndices = (pair.0, index) } } else { focusedIndex = index }; pausePlayback(); render() }

    /// Accept a video file dragged onto the window. The file is appended to
    /// the end of the filmstrip; which on-screen slot shows it depends on the
    /// current mode:
    ///   - Focus: play the dropped video directly.
    ///   - Compare: replace the side the drop landed on.
    /// Right-click mute menu. Focus toggles the single player; side-by-side
    /// offers independent mute control for the left and right videos.
    private func presentMuteMenu(atScreenPoint point: NSPoint) {
        actionsPanel?.dismissChain()
        var entries: [ActionMenuEntry]
        if mode == .compare, viewports.count == 2 {
            let leftMuted = viewports[0].isMuted
            let rightMuted = viewports[1].isMuted
            entries = [
                ActionMenuEntry(title: (leftMuted ? "Unmute Left" : "Mute Left").localized,
                                action: { [weak self] in self?.toggleMute(slot: 0) }),
                ActionMenuEntry(title: (rightMuted ? "Unmute Right" : "Mute Right").localized,
                                action: { [weak self] in self?.toggleMute(slot: 1) }),
            ]
        } else if let viewport = viewports.first {
            entries = [
                ActionMenuEntry(title: (viewport.isMuted ? "Unmute" : "Mute").localized,
                                action: { [weak viewport] in
                    guard let viewport else { return }
                    viewport.setMuted(!viewport.isMuted)
                }),
            ]
        } else {
            return
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
        let panel = ActionMenuPanel(entries: entries)
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
        if let index = activeIndices[safe: activeCompareSlot], infos.indices.contains(index) {
            metaLabel.stringValue = infos[index].filename
        }
    }
    private func removeObservers() { if let observer = timeObserver, !players.isEmpty { players[0].removeTimeObserver(observer) }; timeObserver = nil; if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }; endObserver = nil }
    func windowWillClose(_ notification: Notification) { pausePlayback(); removeObservers(); actionsPanel?.dismissChain(); actionsPanel = nil; infoVisible = false; generation = UUID() }
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
    let index: Int; let player: AVPlayer; private let playerView: AVPlayerView; private let muteButton = InspectToolbarButton(symbol: "speaker.slash.fill", tooltip: "Mute".localized); private let compareDimmer = CALayer(); private let loadingView = ModularImageLoadingView(frame: .zero); private let failureView = LoadFailedAnimationView(frame: .zero); private var statusObservation: NSKeyValueObservation?; var onActivate: (() -> Void)?
    weak var dropTarget: MediaDropCanvasView?
    init(index: Int, player: AVPlayer) { self.index = index; self.player = player; playerView = PassthroughVideoPlayerView(frame: .zero); super.init(frame: .zero); registerForDraggedTypes(MediaDropCanvasView.videoDraggedTypes); wantsLayer = true; layer?.masksToBounds = true; layer?.backgroundColor = PanelStyle.inspectCanvas.cgColor; playerView.controlsStyle = .none; playerView.videoGravity = .resizeAspect; playerView.player = player; playerView.wantsLayer = true; playerView.layer?.cornerRadius = 6; playerView.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine); playerView.layer?.borderWidth = 1; playerView.layer?.masksToBounds = true; addSubview(playerView); addSubview(loadingView); addSubview(failureView); failureView.isHidden = true; compareDimmer.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor; compareDimmer.opacity = 0; layer?.addSublayer(compareDimmer); muteButton.target = self; muteButton.action = #selector(toggleMute); muteButton.updateTooltip("Mute".localized); muteButton.isHidden = true; addSubview(muteButton); observePlayerItem() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); let insetX = max(16, bounds.width * 48 / 1554), insetY = max(12, bounds.height * 20 / 847); let mediaFrame = bounds.insetBy(dx: insetX, dy: insetY); playerView.frame = mediaFrame; compareDimmer.frame = bounds; muteButton.frame = NSRect(x: mediaFrame.maxX - 40, y: mediaFrame.maxY - 40, width: 32, height: 32); let loader = ModularImageLoadingView.preferredSize; loadingView.frame = NSRect(x: bounds.midX - loader.width / 2, y: bounds.midY - loader.height / 2, width: loader.width, height: loader.height); let failed = LoadFailedAnimationView.preferredSize; failureView.frame = NSRect(x: bounds.midX - failed.width / 2, y: bounds.midY - failed.height / 2, width: failed.width, height: failed.height) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropTarget?.acceptsDragging(sender) == true ? .copy : [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropTarget?.acceptsDragging(sender) == true ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { dropTarget?.performDrop(sender) == true }
    func replaceSource(with url: URL) {
        let time = player.currentTime()
        let wasPlaying = player.rate != 0
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        observePlayerItem()
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            if wasPlaying { self?.player.playImmediately(atRate: 1) }
        }
    }
    private func observePlayerItem() {
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
    var isMuted: Bool { player.isMuted }
    func setMuted(_ muted: Bool) { player.isMuted = muted; updateMuteButton() }
    var onActionMenu: ((NSEvent) -> Void)?
    @objc private func toggleMute() { player.isMuted.toggle(); updateMuteButton() }
    private func updateMuteButton() { muteButton.setSymbol(player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"); muteButton.updateTooltip(player.isMuted ? "Mute".localized : "Unmute".localized); muteButton.isActive = !player.isMuted }
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
    func fitToView() { zoomScale = 1; applyZoom() }
    private func applyZoom() {
        let transform = zoomScale > 1.01
            ? CGAffineTransform(scaleX: zoomScale, y: zoomScale)
            : CGAffineTransform.identity
        playerView.layer?.setAffineTransform(transform)
    }
    override func rightMouseDown(with event: NSEvent) {
        if let onActionMenu { onActionMenu(event) } else { super.rightMouseDown(with: event) }
    }
}
private final class PassthroughVideoPlayerView: AVPlayerView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

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
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
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
        layer?.backgroundColor = PanelStyle.resolvedCG(NSColor(srgbRed: 17 / 255, green: 18 / 255, blue: 23 / 255, alpha: 1))
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        layer?.borderWidth = 1
        layer?.cornerRadius = 12
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
