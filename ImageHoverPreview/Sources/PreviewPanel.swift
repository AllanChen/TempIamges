import AppKit
import AVKit
import AVFoundation

class PreviewPanel: NSPanel {
    private let anchorOffset = CGPoint(x: 0, y: 8)
    private let cardCornerRadius: CGFloat = 12
    private let cardPadding: CGFloat = 12
    private let captionHeight: CGFloat = 56
    private let gridSpacing: CGFloat = 8
    private let gridColumns: Int = 2
    private let gridTileSize = NSSize(width: 190, height: 230)

    private var tiles: [MediaTileView] = []
    private var anchorPoint: CGPoint = .zero
    private var currentMode: Mode = .grid
    private var currentInfos: [MediaInfo] = []

    private enum Mode { case singleCard, grid }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Public API

    /// Show the panel with skeleton tiles for each MediaInfo. Tiles get
    /// populated later via updateTile(at:with:).
    func showLoading(infos: [MediaInfo], at mouseLocation: NSPoint) {
        guard !infos.isEmpty else {
            hidePanel()
            return
        }
        teardownTiles()
        anchorPoint = mouseLocation
        currentMode = infos.count == 1 ? .singleCard : .grid
        currentInfos = infos

        let container = buildContainer(infos: infos)
        contentView = container

        relayoutPanel(contentSize: container.frame.size)

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func updateTile(at index: Int, with media: LoadedMedia?) {
        guard tiles.indices.contains(index) else { return }
        let tile = tiles[index]
        if let m = media {
            tile.setLoaded(m)
            if index < currentInfos.count {
                var updatedInfo = currentInfos[index]
                updatedInfo.dimensions = m.naturalSize
                currentInfos[index] = updatedInfo
                tile.updateInfo(updatedInfo)
            }
        } else {
            tile.setFailed()
        }
        if currentMode == .singleCard, tiles.count == 1, let m = media {
            relayoutSingleCard(with: m)
        } else if currentMode == .grid {
            relayoutMasonry()
        }
    }

    // Backwards-compat helpers (used elsewhere in the codebase).
    func showImage(_ image: NSImage, at point: NSPoint) {
        let info = MediaInfo(url: URL(fileURLWithPath: "/dev/null"), isLocal: false, kind: .image,
                             dimensions: image.size, fileSize: nil, duration: nil)
        showLoading(infos: [info], at: point)
        updateTile(at: 0, with: .image(image, info))
    }

    func showImages(_ images: [NSImage], at point: NSPoint) {
        let infos = images.map {
            MediaInfo(url: URL(fileURLWithPath: "/dev/null"), isLocal: false, kind: .image,
                      dimensions: $0.size, fileSize: nil, duration: nil)
        }
        showLoading(infos: infos, at: point)
        for (i, img) in images.enumerated() {
            updateTile(at: i, with: .image(img, infos[i]))
        }
    }

    func showMedia(_ items: [LoadedMedia], at point: NSPoint) {
        let infos = items.map { $0.info }
        showLoading(infos: infos, at: point)
        for (i, m) in items.enumerated() {
            updateTile(at: i, with: m)
        }
    }

    func hidePanel() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.teardownTiles()
        })
    }

    func clearImage() {
        teardownTiles()
        contentView = NSView(frame: contentView?.frame ?? .zero)
    }

    // MARK: - Layout

    private func buildContainer(infos: [MediaInfo]) -> NSView {
        switch currentMode {
        case .singleCard: return buildSingleCard(info: infos[0])
        case .grid:       return buildGrid(infos: infos)
        }
    }

    /// Build the preview container without window-management side-effects.
    /// Used by Xcode Canvas preview so the panel doesn't pop up as a real window.
    func buildPreviewContainer(infos: [MediaInfo]) -> NSView {
        teardownTiles()
        currentMode = infos.count == 1 ? .singleCard : .grid
        currentInfos = infos
        return buildContainer(infos: infos)
    }

    private func buildSingleCard(info: MediaInfo) -> NSView {
        // Initial placeholder size — will be resized once the image dimensions
        // are known (see relayoutSingleCard).
        let imgArea = NSSize(width: 320, height: 240)
        let cardSize = NSSize(width: imgArea.width + cardPadding * 2,
                              height: imgArea.height + captionHeight + cardPadding * 2)
        let container = NSView(frame: NSRect(origin: .zero, size: cardSize))
        container.wantsLayer = true
        container.layer?.cornerRadius = cardCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor

        let tileFrame = NSRect(x: cardPadding, y: cardPadding,
                               width: imgArea.width,
                               height: imgArea.height + captionHeight)
        let tile = MediaTileView(info: info, style: .singleCard, frame: tileFrame, captionHeight: captionHeight)
        tile.onClose = { [weak self] in self?.hidePanel() }
        let infoURL = info.url
        tile.onAction = {
            NSWorkspace.shared.open(infoURL)
        }
        container.addSubview(tile)
        tiles = [tile]
        return container
    }

    private func buildGrid(infos: [MediaInfo]) -> NSView {
        let cols = gridColumns
        let tileWidth: CGFloat = 190
        let captionH: CGFloat = 56
        let spacing = gridSpacing
        let padding = cardPadding

        var colHeights = Array(repeating: padding, count: cols)
        var layouts: [(x: CGFloat, visualY: CGFloat, width: CGFloat, height: CGFloat)] = []

        for info in infos {
            let shortestCol = colHeights.enumerated().min(by: { $0.element < $1.element })?.0 ?? 0
            let x = padding + CGFloat(shortestCol) * (tileWidth + spacing)
            let visualY = colHeights[shortestCol]

            let defaultImageHeight: CGFloat = 140
            let imageHeight: CGFloat
            if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
                imageHeight = tileWidth * (dim.height / dim.width)
            } else {
                imageHeight = defaultImageHeight
            }
            let clampedImageHeight = min(max(imageHeight, 80), 280)
            let tileHeight = clampedImageHeight + captionH

            layouts.append((x: x, visualY: visualY, width: tileWidth, height: tileHeight))
            colHeights[shortestCol] = visualY + tileHeight + spacing
        }

        let maxVisualBottom = colHeights.map { $0 - spacing }.max() ?? padding
        let containerHeight = maxVisualBottom + padding
        let containerWidth = padding * 2 + CGFloat(cols) * tileWidth + CGFloat(cols - 1) * spacing

        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = cardCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor

        var newTiles: [MediaTileView] = []
        for (i, info) in infos.enumerated() {
            guard i < layouts.count else { break }
            let layout = layouts[i]
            let appKitY = containerHeight - layout.visualY - layout.height
            let frame = NSRect(x: layout.x, y: appKitY, width: layout.width, height: layout.height)
            let tile = MediaTileView(info: info, style: .gridTile, frame: frame, captionHeight: captionH)
            container.addSubview(tile)
            newTiles.append(tile)
        }
        tiles = newTiles
        return container
    }

    private func relayoutMasonry() {
        guard currentMode == .grid, !tiles.isEmpty else { return }

        let cols = gridColumns
        let tileWidth: CGFloat = 190
        let captionH: CGFloat = 56
        let spacing = gridSpacing
        let padding = cardPadding

        var colHeights = Array(repeating: padding, count: cols)
        var visualFrames: [NSRect] = []

        for (i, info) in currentInfos.enumerated() {
            guard i < tiles.count else { break }
            let shortestCol = colHeights.enumerated().min(by: { $0.element < $1.element })?.0 ?? 0
            let x = padding + CGFloat(shortestCol) * (tileWidth + spacing)
            let visualY = colHeights[shortestCol]

            let defaultImageHeight: CGFloat = 140
            let imageHeight: CGFloat
            if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
                imageHeight = tileWidth * (dim.height / dim.width)
            } else {
                imageHeight = defaultImageHeight
            }
            let clampedImageHeight = min(max(imageHeight, 80), 280)
            let tileHeight = clampedImageHeight + captionH

            visualFrames.append(NSRect(x: x, y: visualY, width: tileWidth, height: tileHeight))
            colHeights[shortestCol] = visualY + tileHeight + spacing
        }

        let maxVisualBottom = colHeights.map { $0 - spacing }.max() ?? padding
        let containerHeight = maxVisualBottom + padding
        let containerWidth = padding * 2 + CGFloat(cols) * tileWidth + CGFloat(cols - 1) * spacing

        contentView?.frame = NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight)

        for (i, vFrame) in visualFrames.enumerated() {
            guard i < tiles.count else { break }
            let appKitY = containerHeight - vFrame.origin.y - vFrame.height
            let newFrame = NSRect(x: vFrame.origin.x, y: appKitY, width: vFrame.width, height: vFrame.height)
            tiles[i].frame = newFrame
            tiles[i].relayoutChildren()
        }

        relayoutPanel(contentSize: NSSize(width: containerWidth, height: containerHeight))
    }

    private func relayoutSingleCard(with media: LoadedMedia) {
        guard let tile = tiles.first else { return }
        let raw = media.naturalSize
        let maxSize = Preferences.shared.maxPreviewSize
        var dw: CGFloat
        var dh: CGFloat
        if raw.width <= 0 || raw.height <= 0 {
            dw = 320; dh = 240
        } else if raw.width >= raw.height {
            dw = min(raw.width, maxSize)
            dh = dw * (raw.height / raw.width)
        } else {
            dh = min(raw.height, maxSize)
            dw = dh * (raw.width / raw.height)
        }
        dw = max(160, dw)
        dh = max(120, dh)

        let cardSize = NSSize(width: dw + cardPadding * 2,
                              height: dh + captionHeight + cardPadding * 2)
        contentView?.frame = NSRect(origin: .zero, size: cardSize)
        contentView?.layer?.cornerRadius = cardCornerRadius
        tile.frame = NSRect(x: cardPadding, y: cardPadding, width: dw, height: dh + captionHeight)
        tile.relayoutChildren()
        relayoutPanel(contentSize: cardSize)
    }

    private func relayoutPanel(contentSize: NSSize) {
        let frame = ScreenManager.shared.adjustedFrame(for: contentSize, at: anchorPoint, offset: anchorOffset)
        setFrame(frame, display: true)
    }

    private func teardownTiles() {
        for tile in tiles { tile.teardown() }
        tiles.removeAll()
        currentInfos.removeAll()
    }
}

// MARK: - Tile view

private final class MediaTileView: NSView {
    enum Style { case singleCard, gridTile }

    var info: MediaInfo
    let style: Style
    let captionHeight: CGFloat

    private let mediaContainer = NSView()
    private let imageLayer = CALayer()
    private let captionContainer = NSView()
    private let captionGradient = CAGradientLayer()
    private let filenameLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    private var playerView: AVPlayerView?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    // Single-card header overlay
    private let headerOverlay = NSView()
    private let headerGradient = CAGradientLayer()
    private var closeButton: NSButton?
    private var actionButton: NSButton?
    private var headerTitleLabel: NSTextField?

    var onClose: (() -> Void)?
    var onAction: (() -> Void)?

    init(info: MediaInfo, style: Style, frame: NSRect, captionHeight: CGFloat) {
        self.info = info
        self.style = style
        self.captionHeight = captionHeight
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor

        // Media area background (dark), holds image/video layer.
        mediaContainer.wantsLayer = true
        mediaContainer.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        addSubview(mediaContainer)

        imageLayer.contentsGravity = (style == .singleCard) ? .resizeAspect : .resizeAspectFill
        imageLayer.masksToBounds = true
        mediaContainer.layer?.addSublayer(imageLayer)

        // Spinner sits on top of media area until loaded.
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.usesThreadedAnimation = true
        spinner.startAnimation(nil)
        addSubview(spinner)

        // Caption: filename + optional meta line. Grid mode overlays it on the
        // image with a dark gradient; single-card mode places it below.
        captionContainer.wantsLayer = true
        if style == .gridTile {
            captionContainer.layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
            metaLabel.usesSingleLineMode = false
            metaLabel.lineBreakMode = .byWordWrapping
            metaLabel.maximumNumberOfLines = 2
        }
        addSubview(captionContainer)

        filenameLabel.textColor = .white
        filenameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.maximumNumberOfLines = 1
        filenameLabel.stringValue = info.filename
        captionContainer.addSubview(filenameLabel)

        metaLabel.textColor = NSColor(white: 1, alpha: 0.7)
        metaLabel.font = NSFont.systemFont(ofSize: 10)
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.maximumNumberOfLines = 1
        metaLabel.isHidden = true
        captionContainer.addSubview(metaLabel)

        // Single-card header overlay (close button + title + action button)
        if style == .singleCard {
            headerOverlay.wantsLayer = true
            headerGradient.colors = [
                NSColor(white: 0, alpha: 0.6).cgColor,
                NSColor.clear.cgColor
            ]
            headerGradient.startPoint = CGPoint(x: 0.5, y: 1)
            headerGradient.endPoint = CGPoint(x: 0.5, y: 0)
            headerOverlay.layer?.addSublayer(headerGradient)
            addSubview(headerOverlay)

            let closeBtn = NSButton(frame: .zero)
            closeBtn.bezelStyle = .recessed
            closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
            closeBtn.imagePosition = .imageOnly
            closeBtn.isBordered = false
            closeBtn.target = self
            closeBtn.action = #selector(closeTapped)
            closeBtn.contentTintColor = .white
            addSubview(closeBtn)
            closeButton = closeBtn

            let titleLabel = NSTextField(labelWithString: info.filename)
            titleLabel.textColor = .white
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            titleLabel.alignment = .center
            titleLabel.lineBreakMode = .byTruncatingMiddle
            titleLabel.maximumNumberOfLines = 1
            addSubview(titleLabel)
            headerTitleLabel = titleLabel

            let actionBtn = NSButton(frame: .zero)
            actionBtn.bezelStyle = .recessed
            actionBtn.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Download")
            actionBtn.imagePosition = .imageOnly
            actionBtn.isBordered = false
            actionBtn.target = self
            actionBtn.action = #selector(actionTapped)
            actionBtn.contentTintColor = .white
            addSubview(actionBtn)
            actionButton = actionBtn
        }

        relayoutChildren()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func relayoutChildren() {
        switch style {
        case .singleCard:
            let mediaH = bounds.height - captionHeight
            mediaContainer.frame = NSRect(x: 0, y: captionHeight, width: bounds.width, height: mediaH)
            imageLayer.frame = mediaContainer.bounds
            playerView?.frame = mediaContainer.bounds
            captionContainer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: captionHeight)
            spinner.frame = NSRect(x: bounds.midX - 8,
                                   y: captionHeight + mediaH / 2 - 8,
                                   width: 16, height: 16)
            filenameLabel.alignment = .center
            filenameLabel.frame = NSRect(x: 12, y: captionHeight - 26, width: bounds.width - 24, height: 18)
            metaLabel.alignment = .center
            metaLabel.frame = NSRect(x: 12, y: captionHeight - 46, width: bounds.width - 24, height: 14)

            let headerH: CGFloat = 44
            headerOverlay.frame = NSRect(x: 0, y: captionHeight + mediaH - headerH,
                                         width: bounds.width, height: headerH)
            headerGradient.frame = headerOverlay.bounds
            closeButton?.frame = NSRect(x: 8, y: captionHeight + mediaH - 36, width: 28, height: 28)
            headerTitleLabel?.frame = NSRect(x: 44, y: captionHeight + mediaH - 32,
                                             width: bounds.width - 88, height: 20)
            actionButton?.frame = NSRect(x: bounds.width - 36, y: captionHeight + mediaH - 36,
                                         width: 28, height: 28)
        case .gridTile:
            let mediaH = bounds.height - captionHeight
            mediaContainer.frame = NSRect(x: 0, y: captionHeight, width: bounds.width, height: mediaH)
            imageLayer.frame = mediaContainer.bounds
            playerView?.frame = mediaContainer.bounds
            captionContainer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: captionHeight)
            captionGradient.frame = captionContainer.bounds
            spinner.frame = NSRect(x: bounds.midX - 8, y: captionHeight + mediaH / 2 - 8, width: 16, height: 16)
            filenameLabel.alignment = .left
            filenameLabel.frame = NSRect(x: 10, y: captionHeight - 22, width: bounds.width - 20, height: 16)
            metaLabel.alignment = .left
            metaLabel.frame = NSRect(x: 10, y: 6, width: bounds.width - 20, height: captionHeight - 28)
        }
    }

    func setLoaded(_ media: LoadedMedia) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true

        switch media {
        case .image(let img, let info):
            imageLayer.contents = img
            updateCaption(with: info)
        case .video(let url, _, let info):
            attachPlayer(url: url)
            updateCaption(with: info)
        }
    }

    func setFailed() {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        metaLabel.stringValue = "Failed to load"
        metaLabel.isHidden = false
    }

    func updateInfo(_ newInfo: MediaInfo) {
        self.info = newInfo
        updateCaption(with: newInfo)
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func actionTapped() {
        onAction?()
    }

    func teardown() {
        player?.pause()
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player = nil
        playerView?.player = nil
    }

    private func attachPlayer(url: URL) {
        let pv = AVPlayerView(frame: mediaContainer.bounds)
        pv.controlsStyle = .none
        pv.videoGravity = (style == .singleCard) ? .resizeAspect : .resizeAspectFill
        let p = AVPlayer(url: url)
        p.isMuted = true
        pv.player = p
        mediaContainer.addSubview(pv)
        playerView = pv
        player = p

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero); p?.play()
        }
        p.play()
    }

    private func updateCaption(with info: MediaInfo) {
        filenameLabel.stringValue = info.filename

        // Remote items only show the filename per spec. Local items include
        // dimensions / file size / format / duration when available.
        guard info.isLocal else {
            metaLabel.isHidden = true
            return
        }

        var parts: [String] = []
        if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
            parts.append("\(Int(dim.width)) × \(Int(dim.height))")
        }
        if let bytes = info.fileSize {
            parts.append(formatBytes(bytes))
        }
        if !info.formatName.isEmpty {
            parts.append(info.formatName)
        }
        if info.isVideo, let dur = info.duration {
            parts.insert(formatDuration(dur), at: 0)
        }

        if parts.isEmpty {
            metaLabel.isHidden = true
        } else {
            if style == .gridTile {
                metaLabel.stringValue = parts.joined(separator: "\n")
            } else {
                metaLabel.stringValue = parts.joined(separator: " • ")
            }
            metaLabel.isHidden = false
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
