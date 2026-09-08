import AppKit
import AVKit
import AVFoundation

final class VideoCompareWindow: NSWindow, NSWindowDelegate {
    private let infos: [MediaInfo]
    private let players: [AVPlayer]
    private let playerViews: [AVPlayerView]
    private let playButton = NSButton()
    private let timeline = NSSlider()
    private let currentLabel = NSTextField(labelWithString: "0:00")
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let titleLabel = NSTextField(labelWithString: "Video comparison".localized)
    private let root = NSView()
    private var durations: [Double] = [0, 0]
    private var masterIndex = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var currentTime: Double = 0
    private var isScrubbing = false

    init?(infos: [MediaInfo]) {
        guard infos.count == 2, infos.allSatisfy({ $0.kind == .video }) else { return nil }
        self.infos = infos
        let avPlayers = infos.map { playerInfo in
            let player = AVPlayer(url: playerInfo.url)
            player.isMuted = true
            return player
        }
        self.players = avPlayers
        self.playerViews = avPlayers.map { player in
            let view = AVPlayerView(frame: .zero)
            view.player = player
            view.controlsStyle = .none
            view.videoGravity = .resizeAspect
            return view
        }

        super.init(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Video comparison".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = PanelStyle.imageCanvas
        minSize = NSSize(width: 720, height: 520)
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
        buildUI()
        loadDurations()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        root.frame = contentView?.bounds ?? .zero
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.imageCanvas.cgColor
        contentView = root

        for playerView in playerViews {
            playerView.wantsLayer = true
            playerView.layer?.backgroundColor = PanelStyle.imageCanvas.cgColor
            root.addSubview(playerView)
        }

        let footer = PanelStyle.makeBarBlur()
        footer.autoresizingMask = [.width, .minYMargin]
        root.addSubview(footer)

        titleLabel.font = PanelStyle.headline
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.alignment = .center
        root.addSubview(titleLabel)

        playButton.bezelStyle = .recessed
        playButton.isBordered = false
        playButton.imagePosition = .imageOnly
        playButton.contentTintColor = PanelStyle.textPrimary
        playButton.target = self
        playButton.action = #selector(togglePlayback)
        footer.addSubview(playButton)

        timeline.minValue = 0
        timeline.maxValue = 1
        timeline.doubleValue = 0
        timeline.isContinuous = true
        timeline.target = self
        timeline.action = #selector(timelineChanged)
        footer.addSubview(timeline)

        for label in [currentLabel, durationLabel] {
            label.font = PanelStyle.caption
            label.textColor = PanelStyle.textSecondary
            label.alignment = .center
            footer.addSubview(label)
        }
        updatePlayButton()
        layoutViews()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutViews()
    }

    private func layoutViews() {
        let footerHeight: CGFloat = 58
        let titleHeight: CGFloat = 34
        let width = root.bounds.width
        let height = root.bounds.height
        titleLabel.frame = NSRect(x: 18, y: height - titleHeight + 4,
                                  width: width - 36, height: 20)
        let videoRect = NSRect(x: 0, y: footerHeight, width: width,
                               height: max(0, height - footerHeight - titleHeight))
        let gap: CGFloat = 1
        let half = (videoRect.width - gap) / 2
        playerViews[0].frame = NSRect(x: 0, y: videoRect.minY,
                                      width: half, height: videoRect.height)
        playerViews[1].frame = NSRect(x: half + gap, y: videoRect.minY,
                                      width: half, height: videoRect.height)

        guard let footer = root.subviews.first(where: { $0 is NSVisualEffectView }) else { return }
        footer.frame = NSRect(x: 0, y: 0, width: width, height: footerHeight)
        playButton.frame = NSRect(x: 16, y: 17, width: 26, height: 26)
        let left = playButton.frame.maxX + 12
        let right = width - 16
        currentLabel.frame = NSRect(x: left, y: 20, width: 42, height: 16)
        durationLabel.frame = NSRect(x: right - 42, y: 20, width: 42, height: 16)
        timeline.frame = NSRect(x: currentLabel.frame.maxX + 8, y: 22,
                                width: max(80, durationLabel.frame.minX - currentLabel.frame.maxX - 16), height: 14)
    }

    private func loadDurations() {
        for (index, info) in infos.enumerated() {
            let asset = AVURLAsset(url: info.url)
            Task { [weak self] in
                let duration = (try? await asset.load(.duration))?.seconds ?? info.duration ?? 0
                await MainActor.run { self?.setDuration(duration, at: index) }
            }
        }
    }

    private func setDuration(_ duration: Double, at index: Int) {
        guard durations.indices.contains(index) else { return }
        let previousMaster = masterIndex
        durations[index] = max(0, duration.isFinite ? duration : 0)
        masterIndex = durations[1] > durations[0] ? 1 : 0
        let maximum = durations.max() ?? 0
        timeline.maxValue = max(1, maximum)
        durationLabel.stringValue = Self.formatTime(maximum)
        if previousMaster != masterIndex {
            if let observer = timeObserver {
                players[previousMaster].removeTimeObserver(observer)
                timeObserver = nil
            }
            if let observer = endObserver {
                NotificationCenter.default.removeObserver(observer)
                endObserver = nil
            }
        }
        installTimeObserverIfNeeded()
    }

    private func installTimeObserverIfNeeded() {
        guard timeObserver == nil, durations.max() ?? 0 > 0 else { return }
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = players[masterIndex].addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            self.currentTime = min(max(0, time.seconds), self.durations.max() ?? time.seconds)
            self.timeline.doubleValue = self.currentTime
            self.currentLabel.stringValue = Self.formatTime(self.currentTime)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: players[masterIndex].currentItem,
            queue: .main
        ) { [weak self] _ in self?.pausePlayback() }
    }

    @objc private func togglePlayback() {
        players[masterIndex].timeControlStatus == .playing ? pausePlayback() : playPlayback()
    }

    private func playPlayback() {
        syncPlayers(to: currentTime, completion: { [weak self] in
            self?.players.forEach { $0.play() }
            self?.updatePlayButton()
        })
    }

    private func pausePlayback() {
        players.forEach { $0.pause() }
        updatePlayButton()
    }

    @objc private func timelineChanged() {
        let time = timeline.doubleValue
        if !isScrubbing {
            isScrubbing = true
            pausePlayback()
        }
        currentTime = time
        currentLabel.stringValue = Self.formatTime(time)
        syncPlayers(to: time, completion: nil)
        DispatchQueue.main.async { [weak self] in self?.isScrubbing = false }
    }

    private func syncPlayers(to time: Double, completion: (() -> Void)?) {
        let group = DispatchGroup()
        for (index, player) in players.enumerated() {
            let bounded = min(max(0, time), durations[index] > 0 ? durations[index] : time)
            group.enter()
            player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { _ in group.leave() }
        }
        group.notify(queue: .main) { completion?() }
    }

    private func updatePlayButton() {
        let playing = players[masterIndex].timeControlStatus == .playing
        playButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill",
                                   accessibilityDescription: playing ? "Pause".localized : "Play".localized)
        playButton.toolTip = playing ? "Pause".localized : "Play".localized
    }

    func windowWillClose(_ notification: Notification) {
        removeTimeObserver()
        players.forEach { $0.pause() }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            players[masterIndex].removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
