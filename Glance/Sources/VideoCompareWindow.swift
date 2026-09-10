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

    private let canvas = MediaDropCanvasView()
    private let inspectToolbar = InspectIdentityBar()
    private let identityBar = InspectIdentityBar()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let focusButton = InspectToolbarButton(symbol: "play.rectangle", tooltip: "Focus".localized)
    private let compareButton = InspectToolbarButton(symbol: "rectangle.split.2x1", tooltip: "Side by side".localized)
    private let revealButton = InspectToolbarButton(symbol: "folder", tooltip: "Reveal in Finder".localized)
    private let infoButton = InspectToolbarButton(symbol: "info.circle", tooltip: "Video information".localized)
    private let captureButton = InspectToolbarButton(symbol: "camera", tooltip: "Capture frame".localized)
    private let replayButton = InspectToolbarButton(symbol: "arrow.counterclockwise", tooltip: "Replay".localized)
    private let playbackBar = VideoPlaybackBar()
    private let captureFeedback = CaptureFeedbackView()
    private lazy var infoWindow = VideoInfoPanelWindow()
    private var infoVisible = false
    private var isInLiveResize = false
    private let playButton = InspectToolbarButton(symbol: "play.fill", tooltip: "Play".localized)
    private let timeline = WarmVideoTimeline()
    private let currentLabel = NSTextField(labelWithString: "0:00")
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let filmstrip = VideoFilmstripView()
    private var hideWorkItem: DispatchWorkItem?
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
        super.init(contentRect: ScreenManager.shared.contentFrame(for: NSSize(width: 1040, height: 760)),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        title = "Video Inspect".localized
        titleVisibility = .hidden; titlebarAppearsTransparent = true
        appearance = NSAppearance(named: .darkAqua); backgroundColor = PanelStyle.imageCanvas
        minSize = NSSize(width: 640, height: 440); isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true; delegate = self
        compareIndices = videos.count > 1 ? (0, 1) : nil
        mode = startsInCompare && videos.count > 1 ? .compare : .focus
        buildUI(); loadDurations()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        // AppKit calls setFrame repeatedly while it is in its live-resize
        // display cycle. Do not synchronously mutate the content hierarchy
        // from here; that can re-enter AppKit's layout pass and raise an
        // internal NSWindow layout exception.
        super.setFrame(frameRect, display: flag)
    }
    func windowWillStartLiveResize(_ notification: Notification) {
        isInLiveResize = true
        hideWorkItem?.cancel()
    }
    func windowDidResize(_ notification: Notification) {
        layoutContent()
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        isInLiveResize = false
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
        if event.type == .mouseMoved, !isInLiveResize {
            let point = canvas.convert(event.locationInWindow, from: nil)
            if activeVideoFrame.contains(point) { showToolbar() } else { hideToolbar() }
        }
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

    private func buildUI() {
        // Keep the registered drop target at the root of the window so AVKit's
        // layered player surfaces cannot prevent drag-destination discovery.
        contentView = canvas
        let root = canvas
        root.wantsLayer = true; root.layer?.backgroundColor = PanelStyle.imageCanvas.cgColor
        canvas.acceptsExtension = { ext in
            MediaDropCanvasView.videoExtensions.contains(ext)
        }
        canvas.onDrop = { [weak self] url, point in
            self?.handleDroppedVideo(url: url, at: point)
        }
        for (label, font, color) in [(titleLabel, PanelStyle.headline, PanelStyle.textPrimary), (metaLabel, PanelStyle.caption, PanelStyle.textSecondary)] {
            label.font = font; label.textColor = color; label.lineBreakMode = .byTruncatingMiddle; label.maximumNumberOfLines = 1; identityBar.addSubview(label)
        }
        canvas.addSubview(identityBar)
        focusButton.target = self; focusButton.action = #selector(focusTapped)
        compareButton.target = self; compareButton.action = #selector(compareTapped)
        revealButton.target = self; revealButton.action = #selector(revealTapped)
        infoButton.target = self; infoButton.action = #selector(infoTapped)
        captureButton.target = self; captureButton.action = #selector(captureTapped)
        replayButton.target = self; replayButton.action = #selector(replayTapped)
        [focusButton, compareButton, captureButton, replayButton, infoButton, revealButton].forEach { inspectToolbar.addSubview($0) }; canvas.addSubview(inspectToolbar)
        playButton.target = self; playButton.action = #selector(playTapped)
        timeline.onChange = { [weak self] value in self?.seek(to: value) }
        for label in [currentLabel, durationLabel] { label.font = PanelStyle.caption; label.textColor = PanelStyle.textSecondary; label.alignment = .center }
        [playButton, timeline, currentLabel, durationLabel].forEach { playbackBar.addSubview($0) }
        playbackBar.autoresizingMask = [.width, .minYMargin]
        canvas.addSubview(playbackBar)
        filmstrip.onSelect = { [weak self] index in self?.selectVideo(index) }; canvas.addSubview(filmstrip)
        inspectToolbar.isHidden = true; inspectToolbar.alphaValue = 0; identityBar.isHidden = true; identityBar.alphaValue = 0; filmstrip.isHidden = true; filmstrip.alphaValue = 0; playbackBar.isHidden = true; playbackBar.alphaValue = 0
        captureFeedback.isHidden = true
        canvas.addSubview(captureFeedback, positioned: .above, relativeTo: nil)
        render()
    }

    private var activeIndices: [Int] {
        if mode == .compare, let pair = compareIndices { return [pair.0, pair.1] }
        return infos.indices.contains(focusedIndex) ? [focusedIndex] : []
    }
    private var activeVideoFrame: NSRect { viewports.reduce(.zero) { $0.union($1.frame) } }

    private func layoutContent() {
        let b = canvas.bounds; let top: CGFloat = 44; let identityH: CGFloat = 54
        identityBar.frame = NSRect(x: 0, y: b.height - identityH, width: b.width, height: identityH)
        titleLabel.frame = NSRect(x: 18, y: 29, width: b.width - 36, height: 17); metaLabel.frame = NSRect(x: 18, y: 9, width: b.width - 36, height: 15)
        // Keep the compact toolbar geometry shared by image and video inspect.
        inspectToolbar.frame = NSRect(x: 0, y: b.height - top, width: b.width, height: top)
        let buttonSize: CGFloat = 24; var x = b.width - 12 - buttonSize
        [revealButton, infoButton, replayButton, captureButton, compareButton, focusButton].forEach {
            // Square bounds preserve a 1:1 icon hit area and center it in the bar.
            $0.frame = NSRect(x: x, y: (top - buttonSize) / 2,
                              width: buttonSize, height: buttonSize)
            x -= buttonSize + 8
        }
        let videoRect = NSRect(x: 0, y: 0, width: b.width, height: b.height)
        if mode == .compare, activeIndices.count == 2 {
            let gap: CGFloat = 1; let w = (videoRect.width - gap) / 2
            viewports[safe: 0]?.frame = NSRect(x: 0, y: videoRect.minY, width: w, height: videoRect.height)
            viewports[safe: 1]?.frame = NSRect(x: w + gap, y: videoRect.minY, width: w, height: videoRect.height)
        } else { viewports[safe: 0]?.frame = videoRect; viewports[safe: 1]?.frame = .zero }
        playbackBar.frame = NSRect(x: 0, y: 0, width: b.width, height: 48)
        playButton.frame = NSRect(x: 16, y: 12, width: 24, height: 24); currentLabel.frame = NSRect(x: 50, y: 16, width: 42, height: 15); durationLabel.frame = NSRect(x: b.width - 58, y: 16, width: 42, height: 15)
        timeline.frame = NSRect(x: 98, y: 15, width: max(80, b.width - 166), height: 18)
        filmstrip.frame = NSRect(x: 0, y: identityH + 12, width: b.width, height: 56)
        captureFeedback.frame = b
    }

    private func render() {
        generation = UUID(); viewports.forEach { $0.removeFromSuperview() }; viewports.removeAll(); players.forEach { $0.pause() }; players.removeAll(); removeObservers(); isPlaying = false; currentTime = 0
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
        canvas.addSubview(inspectToolbar, positioned: .above, relativeTo: nil)
        canvas.addSubview(captureFeedback, positioned: .above, relativeTo: nil)
        titleLabel.stringValue = ""
        metaLabel.stringValue = ""
        focusButton.isEnabled = infos.count > 1; compareButton.isEnabled = infos.count > 1; focusButton.isActive = mode == .focus; compareButton.isActive = mode == .compare
        revealButton.isEnabled = activeIndices.contains { infos[$0].isLocal }
        infoButton.isActive = infoVisible
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
    private func updateTimeline() { timeline.maximum = maximumDuration; timeline.value = currentTime; currentLabel.stringValue = Self.formatTime(currentTime); durationLabel.stringValue = Self.formatTime(maximumDuration); playButton.setSymbol(isPlaying ? "pause.fill" : "play.fill") }
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
    @objc private func revealTapped() { for index in activeIndices where infos[index].isLocal { NSWorkspace.shared.activateFileViewerSelecting([infos[index].url]); break } }
    @objc private func infoTapped() {
        infoVisible.toggle(); infoButton.isActive = infoVisible
        if infoVisible {
            refreshInfoPanel()
            positionInfoWindow()
            // Attach as a child window: ordered just above the main window, so
            // a window covering the main window also covers the info panel.
            addChildWindow(infoWindow, ordered: .above)
        } else {
            removeChildWindow(infoWindow)
            infoWindow.orderOut(nil)
        }
    }
    private func refreshInfoPanel() {
        guard infoVisible else { return }
        infoWindow.update(infos: infos, indices: activeIndices, durations: durations, metadata: videoMetadata)
    }
    private func positionInfoWindow() {
        // Dock to the right of the main window, matching ImageInspectWindow's
        // info panel: same 320 width, same 2pt gap, full window height.
        let width: CGFloat = 320
        let gap: CGFloat = 2
        let mainFrame = frame
        var origin = NSPoint(x: mainFrame.maxX + gap, y: mainFrame.minY)
        let size = NSSize(width: width, height: mainFrame.height)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            if origin.x + width > visible.maxX {
                origin.x = max(visible.minX, mainFrame.minX - width - gap)
            }
            origin.y = min(max(visible.minY, origin.y), visible.maxY - size.height)
        }
        infoWindow.setFrame(NSRect(origin: origin, size: size), display: true)
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
        let entries: [ActionMenuEntry]
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
                                action: { [weak self, weak viewport] in
                    guard let viewport else { return }
                    viewport.setMuted(!viewport.isMuted)
                }),
            ]
        } else {
            return
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
    private func showToolbar() {
        guard !isInLiveResize else { return }
        hideWorkItem?.cancel()
        [inspectToolbar, filmstrip, playbackBar].forEach { $0.isHidden = false }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.18
            [inspectToolbar, filmstrip, playbackBar].forEach { $0.animator().alphaValue = 1 }
        }
    }
    private func hideToolbar() {
        guard !isInLiveResize else { return }
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isInLiveResize else { return }
            NSAnimationContext.runAnimationGroup({ c in
                c.duration = 0.18
                [self.inspectToolbar, self.filmstrip, self.playbackBar].forEach { $0.animator().alphaValue = 0 }
            }) { [weak self] in
                [self?.inspectToolbar, self?.filmstrip, self?.playbackBar].compactMap { $0 }.forEach { $0.isHidden = true }
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
    private func removeObservers() { if let observer = timeObserver, !players.isEmpty { players[0].removeTimeObserver(observer) }; timeObserver = nil; if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }; endObserver = nil }
    func windowWillClose(_ notification: Notification) { pausePlayback(); removeObservers(); actionsPanel?.dismissChain(); actionsPanel = nil; removeChildWindow(infoWindow); infoWindow.orderOut(nil); infoVisible = false; generation = UUID() }
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
    init(index: Int, player: AVPlayer) { self.index = index; self.player = player; playerView = PassthroughVideoPlayerView(frame: .zero); super.init(frame: .zero); registerForDraggedTypes(MediaDropCanvasView.videoDraggedTypes); wantsLayer = true; layer?.backgroundColor = PanelStyle.imageCanvas.cgColor; playerView.controlsStyle = .none; playerView.videoGravity = .resizeAspect; playerView.player = player; addSubview(playerView); addSubview(loadingView); addSubview(failureView); failureView.isHidden = true; compareDimmer.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor; compareDimmer.opacity = 0; layer?.addSublayer(compareDimmer); muteButton.target = self; muteButton.action = #selector(toggleMute); addSubview(muteButton); observePlayerItem() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { playerView.frame = bounds; compareDimmer.frame = bounds; muteButton.frame = NSRect(x: bounds.maxX - 40, y: bounds.maxY - 40 - 44, width: 24, height: 24); let loader = ModularImageLoadingView.preferredSize; loadingView.frame = NSRect(x: bounds.midX - loader.width / 2, y: bounds.midY - loader.height / 2, width: loader.width, height: loader.height); let failed = LoadFailedAnimationView.preferredSize; failureView.frame = NSRect(x: bounds.midX - failed.width / 2, y: bounds.midY - failed.height / 2, width: failed.width, height: failed.height) }
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
    private func updateMuteButton() { muteButton.setSymbol(player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"); muteButton.toolTip = player.isMuted ? "Mute".localized : "Unmute".localized; muteButton.isActive = !player.isMuted }
    override func mouseDown(with event: NSEvent) { onActivate?(); super.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) {
        if let onActionMenu { onActionMenu(event) } else { super.rightMouseDown(with: event) }
    }
}
private final class PassthroughVideoPlayerView: AVPlayerView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

private final class WarmVideoTimeline: NSView {
    var value = 0.0 { didSet { needsDisplay = true } }; var maximum = 1.0 { didSet { needsDisplay = true } }; var onChange: ((Double) -> Void)?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { let track = NSRect(x: 2, y: bounds.midY - 2, width: max(1, bounds.width - 4), height: 4); PanelStyle.controlFill.setFill(); NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill(); let f = maximum > 0 ? min(1, max(0, value / maximum)) : 0; PanelStyle.warmCue.setFill(); NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * f, height: track.height), xRadius: 2, yRadius: 2).fill(); NSBezierPath(ovalIn: NSRect(x: track.minX + track.width * f - 5, y: bounds.midY - 5, width: 10, height: 10)).fill() }
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
            item.loadThumbnail(from: infos[index].url)
            item.onClick = { [weak self] in self?.onSelect?(index) }
            addSubview(item)
        }
        layoutItems()
    }
    private func layoutItems() {
        let w: CGFloat = 48; let gap: CGFloat = 8
        let total = CGFloat(subviews.count) * w + CGFloat(max(0, subviews.count - 1)) * gap
        var x = (bounds.width - total) / 2
        for item in subviews {
            item.frame = NSRect(x: x, y: 3, width: w, height: 50)
            x += w + gap
        }
    }
    override func layout() { super.layout(); layoutItems() }
}
private final class VideoFilmstripItem: NSView {
    var onClick: (() -> Void)?
    // Frosted, translucent black behind the thumbnail (same frosted bar
    // component as the toolbars) instead of a solid black fill.
    private let blur = InspectIdentityBar()
    private let imageView = NSImageView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        addSubview(blur)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        imageView.contentTintColor = PanelStyle.textTertiary
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    // Selection is communicated by the warm-cue border only (mirrors the image
    // filmstrip); the frosted background stays the same either way.
    func configure(selected: Bool, compared: Bool) { layer?.borderWidth = selected || compared ? 2 : 0; layer?.borderColor = PanelStyle.warmCue.cgColor }
    func loadThumbnail(from url: URL) { DispatchQueue.global(qos: .userInitiated).async { [weak self] in let generator = AVAssetImageGenerator(asset: AVAsset(url: url)); generator.appliesPreferredTrackTransform = true; guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return }; DispatchQueue.main.async { self?.imageView.image = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height))) } } }
    override func layout() { blur.frame = bounds; imageView.frame = bounds.insetBy(dx: 3, dy: 3) }; override func mouseDown(with event: NSEvent) { onClick?() }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class VideoPlaybackBar: NSVisualEffectView {
    private let tintLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        tintLayer.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
        layer?.addSublayer(tintLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        CATransaction.commit()
    }
}

private final class VideoInfoPanelWindow: NSPanel {
    // Same chrome and card layout as the image info panel: a 320-wide window
    // hosting a scrolling column of info blocks. Attached to the main window
    // as a child while visible; not floating, so it shares the main window's
    // occlusion behavior.
    private let panel = ImageDifferencePanel()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 320, height: 240)
        contentMaxSize = NSSize(width: 320, height: 10000)
        title = "Video information".localized
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Frosted, translucent black chrome instead of a solid surface color.
        isOpaque = false
        backgroundColor = .clear
        if let content = contentView {
            let frost = PanelStyle.makeFrostedBase(cornerRadius: 0)
            frost.frame = content.bounds
            frost.autoresizingMask = [.width, .height]
            content.addSubview(frost)
        }
        panel.frame = contentView?.bounds ?? .zero
        panel.autoresizingMask = [.width, .height]
        contentView?.addSubview(panel)
    }

    func update(infos: [MediaInfo], indices: [Int], durations: [Double],
                metadata: [VideoTechnicalMetadata?]) {
        let items: [(index: Int, info: MediaInfo, rows: [(String, String)])] = indices.compactMap { index in
            guard infos.indices.contains(index) else { return nil }
            return (index, infos[index], Self.rows(for: infos[index],
                                                   metadata: metadata[safe: index] ?? nil,
                                                   duration: durations[safe: index] ?? 0))
        }
        panel.show(items: items)
    }

    private static func rows(for info: MediaInfo, metadata: VideoTechnicalMetadata?,
                             duration: Double) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let size = info.dimensions, size.width > 0, size.height > 0 {
            rows.append(("Dimensions".localized, "\(Int(size.width)) × \(Int(size.height)) px"))
            rows.append(("Aspect ratio".localized, String(format: "%.3f", size.width / size.height)))
        }
        if let fps = metadata?.fps, fps > 0 {
            rows.append(("Frame rate".localized, String(format: "%g fps", Double(fps))))
        }
        if info.formatName.isDisplayableValue { rows.append(("Format".localized, info.formatName)) }
        if let codec = metadata?.videoCodec, codec.isDisplayableValue {
            rows.append(("Video codec".localized, codec))
        }
        if let bitrate = metadata?.videoBitrate, bitrate > 0 {
            rows.append(("Video bitrate".localized, formatBitrate(bitrate)))
        }
        if let codec = metadata?.audioCodec, codec.isDisplayableValue {
            rows.append(("Audio codec".localized, codec))
        }
        if duration > 0 { rows.append(("Duration".localized, formatTime(duration))) }
        if let bytes = info.fileSize {
            rows.append(("File size".localized, ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
        }
        if info.isLocal { rows.append(("Path".localized, info.url.path)) }
        return rows
    }

    private static func formatBitrate(_ bps: Float) -> String {
        if bps >= 1_000_000 { return String(format: "%.1f Mbps", Double(bps) / 1_000_000) }
        if bps >= 1_000 { return String(format: "%.0f kbps", Double(bps) / 1_000) }
        return String(format: "%.0f bps", Double(bps))
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
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
