import AppKit
import AVKit
import AVFoundation

class PreviewPanel: NSPanel {
    // MARK: - Layout constants
    private let anchorOffset = CGPoint(x: 0, y: 8)
    private let panelCornerRadius: CGFloat = 16
    private let headerHeight: CGFloat = 48
    private let bottomBarHeight: CGFloat = 72

    // Single-card middle area (around the dark inset)
    private let middlePadding: CGFloat = 18
    private let insetCornerRadius: CGFloat = 18
    private let insetTopArea: CGFloat = 48        // space above the image for anchor + filename pill
    private let metaPillArea: CGFloat = 56        // filename/meta pill below image
    private let filmstripHeight: CGFloat = 56
    private let dotsHeight: CGFloat = 18
    private let insetHorizontalPad: CGFloat = 16  // space between image and dark inset sides
    private let insetBottomPad: CGFloat = 10

    // Multi-image masonry
    private let masonryHorizontalPad: CGFloat = 8
    private let masonryTopPad: CGFloat = 6      // small gap below header
    private let masonryBottomPad: CGFloat = 8
    private let masonryColumnSpacing: CGFloat = 8
    private let masonryRowSpacing: CGFloat = 8
    private let masonryColumnWidth: CGFloat = 174
    private let masonryColumns: Int = 2
    private let masonryMinCardHeight: CGFloat = 110
    private let masonryMaxCardHeight: CGFloat = 280

    // Colors
    fileprivate static let panelBackground   = NSColor.white
    fileprivate static let middleBackground  = NSColor(white: 0.96, alpha: 1)
    fileprivate static let darkInset         = NSColor(white: 0.07, alpha: 1)
    fileprivate static let bottomBar         = NSColor(white: 0.32, alpha: 1)
    fileprivate static let separator         = NSColor(white: 0.88, alpha: 1)
    fileprivate static let pillBackground    = NSColor(white: 1, alpha: 0.10)
    fileprivate static let pillBackgroundLight = NSColor(white: 1, alpha: 0.16)
    fileprivate static let textDark          = NSColor(white: 0.15, alpha: 1)
    fileprivate static let textSecondary     = NSColor(white: 0.45, alpha: 1)
    fileprivate static let textOnDark        = NSColor.white
    fileprivate static let textOnDarkSecondary = NSColor(white: 1, alpha: 0.70)
    fileprivate static let thumbPlaceholder  = NSColor(white: 0.85, alpha: 1)
    fileprivate static let filmstripBorder   = NSColor.systemBlue
    fileprivate static let accentBlue        = NSColor.systemBlue

    private var tiles: [MediaTileView] = []
    private var anchorPoint: CGPoint = .zero
    private var currentMode: Mode = .grid
    private var currentInfos: [MediaInfo] = []
    private var selectedIndex: Int = 0

    // Single-card view references (used to update labels once load completes).
    private weak var singleHeaderTitle: NSTextField?
    private weak var bottomFilenameLabel: NSTextField?
    private weak var bottomDimsLabel: NSTextField?
    private weak var bottomSizeLabel: NSTextField?
    private weak var topPillLabel: NSTextField?
    private weak var metaPillFilename: NSTextField?
    private weak var metaPillMeta: NSTextField?
    private weak var singleCloseBtn: NSButton?
    private weak var singlePinBtn: NSButton?

    /// When pinned, hidePanel() is ignored and the close (X) button shows.
    /// New previews via showLoading() reset this to false.
    private var isPinned: Bool = false

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

    func showLoading(infos: [MediaInfo], at mouseLocation: NSPoint) {
        guard !infos.isEmpty else {
            forceHidePanel()
            return
        }
        teardownTiles()
        // A new preview replaces whatever was pinned.
        isPinned = false
        anchorPoint = mouseLocation
        currentMode = infos.count == 1 ? .singleCard : .grid
        currentInfos = infos
        selectedIndex = 0

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
                if currentMode == .singleCard, index == 0 {
                    singleHeaderTitle?.stringValue = updatedInfo.filename
                }
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

    /// Auto-hide path. Suppressed when the user has pinned the panel.
    func hidePanel() {
        guard !isPinned else { return }
        forceHidePanel()
    }

    /// Always hide, regardless of pinned state (used by the X button).
    private func forceHidePanel() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isPinned = false
            self?.orderOut(nil)
            self?.teardownTiles()
        })
    }

    func clearImage() {
        teardownTiles()
        contentView = NSView(frame: contentView?.frame ?? .zero)
    }

    // MARK: - Container building

    private func buildContainer(infos: [MediaInfo]) -> NSView {
        switch currentMode {
        case .singleCard: return buildSingleCard(info: infos[0])
        case .grid:       return buildList(infos: infos)
        }
    }

    func buildPreviewContainer(infos: [MediaInfo]) -> NSView {
        teardownTiles()
        currentMode = infos.count == 1 ? .singleCard : .grid
        currentInfos = infos
        selectedIndex = 0
        return buildContainer(infos: infos)
    }

    // MARK: - Single-card layout

    private func buildSingleCard(info: MediaInfo) -> NSView {
        // Placeholder image dimensions — refined in relayoutSingleCard().
        let imgSize = NSSize(width: 360, height: 270)
        let totalWidth = imgSize.width
        let totalHeight = headerHeight + imgSize.height

        let container = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = panelCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = Self.darkInset.cgColor

        // Header (white)
        let header = makeHeaderBar(
            width: totalWidth,
            title: info.filename,
            leftSymbol: "xmark",
            leftAction: #selector(closeButtonTapped),
            rightSymbol: "pin.fill",
            rightAction: #selector(actionButtonTapped),
            captureTitleForSingle: true
        )
        header.frame.origin = CGPoint(x: 0, y: totalHeight - headerHeight)
        container.addSubview(header)

        // Image fills the rest of the panel; metadata overlay sits on top of the image.
        let tileFrame = NSRect(x: 0, y: 0, width: totalWidth, height: imgSize.height)
        let tile = MediaTileView(info: info, style: .singleCard, frame: tileFrame)
        tile.onClose = { [weak self] in self?.hidePanel() }
        let infoURL = info.url
        tile.onAction = { NSWorkspace.shared.open(infoURL) }
        container.addSubview(tile)

        tiles = [tile]
        return container
    }

    // MARK: - Multi-image masonry layout

    private func buildList(infos: [MediaInfo]) -> NSView {
        let cols = masonryColumns
        let colW = masonryColumnWidth
        let spacing = masonryColumnSpacing
        let rowSpacing = masonryRowSpacing

        // Two-column shortest-column packing.
        var colHeights = Array(repeating: masonryTopPad, count: cols)
        var visualLayouts: [(x: CGFloat, visualY: CGFloat, w: CGFloat, h: CGFloat)] = []

        for info in infos {
            let shortest = colHeights.enumerated().min(by: { $0.element < $1.element })?.0 ?? 0
            let x = masonryHorizontalPad + CGFloat(shortest) * (colW + spacing)
            let visualY = colHeights[shortest]

            let aspect: CGFloat
            if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
                aspect = dim.height / dim.width
            } else {
                aspect = 0.75
            }
            let rawHeight = colW * aspect
            let cardHeight = min(max(rawHeight, masonryMinCardHeight), masonryMaxCardHeight)

            visualLayouts.append((x: x, visualY: visualY, w: colW, h: cardHeight))
            colHeights[shortest] = visualY + cardHeight + rowSpacing
        }

        let cardsBottomVisualY = (colHeights.map { $0 - rowSpacing }.max() ?? masonryTopPad)
        let cardsTotalHeight = cardsBottomVisualY + masonryBottomPad
        let contentWidth = CGFloat(cols) * colW + CGFloat(cols - 1) * spacing + masonryHorizontalPad * 2
        let totalHeight = headerHeight + cardsTotalHeight

        let container = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: totalHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = panelCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = Self.panelBackground.cgColor

        let title = "preview_gallery_(\(infos.count))"
        let header = makeHeaderBar(
            width: contentWidth,
            title: title,
            leftSymbol: "chevron.left",
            leftAction: #selector(closeButtonTapped),
            rightSymbol: "arrow.down.to.line",
            rightAction: #selector(actionButtonTapped),
            captureTitleForSingle: false
        )
        header.frame.origin = CGPoint(x: 0, y: totalHeight - headerHeight)
        container.addSubview(header)

        var newTiles: [MediaTileView] = []
        for (i, info) in infos.enumerated() {
            let layout = visualLayouts[i]
            // Convert visual Y (top-of-card-area, increasing downward) → AppKit Y.
            let appKitY = (totalHeight - headerHeight) - layout.visualY - layout.h
            let frame = NSRect(x: layout.x, y: appKitY, width: layout.w, height: layout.h)
            let tile = MediaTileView(info: info, style: .masonry, frame: frame)
            container.addSubview(tile)
            newTiles.append(tile)
        }
        tiles = newTiles
        return container
    }

    private func relayoutMasonry() {
        guard currentMode == .grid, !tiles.isEmpty else { return }
        let cols = masonryColumns
        let colW = masonryColumnWidth
        let spacing = masonryColumnSpacing
        let rowSpacing = masonryRowSpacing

        var colHeights = Array(repeating: masonryTopPad, count: cols)
        var visualLayouts: [(x: CGFloat, visualY: CGFloat, w: CGFloat, h: CGFloat)] = []

        for info in currentInfos {
            let shortest = colHeights.enumerated().min(by: { $0.element < $1.element })?.0 ?? 0
            let x = masonryHorizontalPad + CGFloat(shortest) * (colW + spacing)
            let visualY = colHeights[shortest]
            let aspect: CGFloat
            if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
                aspect = dim.height / dim.width
            } else {
                aspect = 0.75
            }
            let rawHeight = colW * aspect
            let cardHeight = min(max(rawHeight, masonryMinCardHeight), masonryMaxCardHeight)
            visualLayouts.append((x: x, visualY: visualY, w: colW, h: cardHeight))
            colHeights[shortest] = visualY + cardHeight + rowSpacing
        }

        let cardsBottomVisualY = (colHeights.map { $0 - rowSpacing }.max() ?? masonryTopPad)
        let cardsTotalHeight = cardsBottomVisualY + masonryBottomPad
        let contentWidth = CGFloat(cols) * colW + CGFloat(cols - 1) * spacing + masonryHorizontalPad * 2
        let totalHeight = headerHeight + cardsTotalHeight

        guard let container = contentView else { return }
        container.frame = NSRect(x: 0, y: 0, width: contentWidth, height: totalHeight)

        // Reposition header (always the last-found view with title tag 3) and tiles.
        for sv in container.subviews where sv !== container {
            if sv.subviews.contains(where: { $0.tag == 3 }) {
                sv.frame = NSRect(x: 0, y: totalHeight - headerHeight,
                                  width: contentWidth, height: headerHeight)
            }
        }

        for (i, layout) in visualLayouts.enumerated() where i < tiles.count {
            let appKitY = (totalHeight - headerHeight) - layout.visualY - layout.h
            tiles[i].frame = NSRect(x: layout.x, y: appKitY, width: layout.w, height: layout.h)
            tiles[i].relayoutChildren()
        }
        relayoutPanel(contentSize: NSSize(width: contentWidth, height: totalHeight))
    }

    // MARK: - Header builder

    private func makeHeaderBar(width: CGFloat, title: String,
                               leftSymbol: String, leftAction: Selector,
                               rightSymbol: String, rightAction: Selector,
                               captureTitleForSingle: Bool) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Self.panelBackground.cgColor

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = Self.separator.cgColor
        sep.autoresizingMask = [.width]
        bar.addSubview(sep)

        let leftBtn = makeIconButton(symbol: leftSymbol, action: leftAction, tint: Self.textDark)
        leftBtn.frame = NSRect(x: 12, y: (headerHeight - 24) / 2, width: 24, height: 24)
        leftBtn.tag = 1
        bar.addSubview(leftBtn)

        let rightBtn = makeIconButton(symbol: rightSymbol, action: rightAction, tint: Self.textDark)
        rightBtn.frame = NSRect(x: width - 36, y: (headerHeight - 24) / 2, width: 24, height: 24)
        rightBtn.tag = 2
        bar.addSubview(rightBtn)

        if captureTitleForSingle {
            singleCloseBtn = leftBtn
            singlePinBtn = rightBtn
            // X is only visible after the user pins.
            leftBtn.isHidden = !isPinned
            rightBtn.contentTintColor = isPinned ? .systemRed : Self.textDark
        }

        let titleLbl = NSTextField(labelWithString: title)
        titleLbl.textColor = Self.textDark
        titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLbl.alignment = .center
        titleLbl.lineBreakMode = .byTruncatingMiddle
        titleLbl.maximumNumberOfLines = 1
        titleLbl.frame = NSRect(x: 48, y: (headerHeight - 18) / 2, width: width - 96, height: 18)
        titleLbl.tag = 3
        bar.addSubview(titleLbl)
        if captureTitleForSingle {
            singleHeaderTitle = titleLbl
        }

        return bar
    }

    private func makeIconButton(symbol: String, action: Selector, tint: NSColor) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .recessed
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        btn.imagePosition = .imageOnly
        btn.isBordered = false
        btn.target = self
        btn.action = action
        btn.contentTintColor = tint
        return btn
    }

    // MARK: - Pills (inside dark inset)

    /// Small rounded badge with white text on a translucent dark fill.
    private func makePill(text: String, light: Bool) -> NSView {
        let lbl = NSTextField(labelWithString: text)
        lbl.textColor = .white
        lbl.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        lbl.lineBreakMode = .byTruncatingMiddle
        lbl.maximumNumberOfLines = 1
        lbl.tag = 99

        let textSize = lbl.intrinsicContentSize
        let padding: CGFloat = 10
        let pill = NSView(frame: NSRect(x: 0, y: 0,
                                        width: min(textSize.width + padding * 2, 200),
                                        height: 22))
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 11
        pill.layer?.masksToBounds = true
        pill.layer?.backgroundColor = (light ? Self.pillBackgroundLight : Self.pillBackground).cgColor

        lbl.frame = NSRect(x: padding, y: 3, width: pill.bounds.width - padding * 2, height: 16)
        pill.addSubview(lbl)
        return pill
    }

    /// Multi-line metadata pill shown below the image inside the dark inset.
    private func makeMetaPill(info: MediaInfo) -> NSView {
        let pill = NSView(frame: .zero)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 10
        pill.layer?.masksToBounds = true
        pill.layer?.backgroundColor = Self.pillBackground.cgColor

        let name = NSTextField(labelWithString: info.filename)
        name.textColor = .white
        name.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        name.alignment = .center
        name.lineBreakMode = .byTruncatingMiddle
        name.maximumNumberOfLines = 1
        pill.addSubview(name)
        metaPillFilename = name

        let meta = NSTextField(labelWithString: metaLineString(for: info))
        meta.textColor = Self.textOnDarkSecondary
        meta.font = NSFont.systemFont(ofSize: 10)
        meta.alignment = .center
        meta.lineBreakMode = .byTruncatingTail
        meta.maximumNumberOfLines = 2
        meta.usesSingleLineMode = false
        pill.addSubview(meta)
        metaPillMeta = meta

        // Frame children once the pill has its frame set:
        DispatchQueue.main.async { [weak pill, weak name, weak meta] in
            guard let pill = pill else { return }
            let w = pill.bounds.width
            let h = pill.bounds.height
            name?.frame = NSRect(x: 8, y: h - 18, width: w - 16, height: 14)
            meta?.frame = NSRect(x: 8, y: 4, width: w - 16, height: h - 22)
        }
        return pill
    }

    // MARK: - Filmstrip & dots

    private func makeFilmstrip(width: CGFloat, count: Int, selected: Int) -> NSView {
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: width, height: filmstripHeight))

        let visibleCount = min(5, max(count, 1))
        let thumbH: CGFloat = 44
        let thumbW: CGFloat = 44
        let gap: CGFloat = 6
        let totalW = CGFloat(visibleCount) * thumbW + CGFloat(visibleCount - 1) * gap
        var x = (width - totalW) / 2
        let y = (filmstripHeight - thumbH) / 2

        for i in 0..<visibleCount {
            let thumb = NSView(frame: NSRect(x: x, y: y, width: thumbW, height: thumbH))
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 6
            thumb.layer?.masksToBounds = true
            thumb.layer?.backgroundColor = Self.thumbPlaceholder.cgColor
            if i == selected {
                thumb.layer?.borderColor = Self.filmstripBorder.cgColor
                thumb.layer?.borderWidth = 2
            }
            strip.addSubview(thumb)
            x += thumbW + gap
        }
        return strip
    }

    private func makeDots(width: CGFloat, count: Int, selected: Int) -> NSView {
        let dotsView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: dotsHeight))
        let visibleCount = min(5, max(count, 1))
        let dotSize: CGFloat = 5
        let gap: CGFloat = 5
        let totalW = CGFloat(visibleCount) * dotSize + CGFloat(visibleCount - 1) * gap
        var x = (width - totalW) / 2
        let y = (dotsHeight - dotSize) / 2

        for i in 0..<visibleCount {
            let dot = NSView(frame: NSRect(x: x, y: y, width: dotSize, height: dotSize))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = dotSize / 2
            dot.layer?.backgroundColor = (i == selected
                ? NSColor.white
                : NSColor(white: 1, alpha: 0.35)).cgColor
            dotsView.addSubview(dot)
            x += dotSize + gap
        }
        return dotsView
    }

    // MARK: - Bottom info bar

    private func makeBottomInfoBar(width: CGFloat, info: MediaInfo) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: bottomBarHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Self.bottomBar.cgColor

        let nameLbl = NSTextField(labelWithString: info.filename)
        nameLbl.textColor = Self.textOnDark
        nameLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLbl.lineBreakMode = .byTruncatingMiddle
        nameLbl.maximumNumberOfLines = 1
        nameLbl.frame = NSRect(x: 16, y: bottomBarHeight - 26, width: width - 32, height: 16)
        nameLbl.autoresizingMask = [.width]
        bar.addSubview(nameLbl)
        bottomFilenameLabel = nameLbl

        let dimsLbl = NSTextField(labelWithString: dimsString(for: info))
        dimsLbl.textColor = Self.textOnDarkSecondary
        dimsLbl.font = NSFont.systemFont(ofSize: 11)
        dimsLbl.lineBreakMode = .byTruncatingTail
        dimsLbl.maximumNumberOfLines = 1
        dimsLbl.frame = NSRect(x: 16, y: bottomBarHeight - 44, width: width - 32, height: 14)
        dimsLbl.autoresizingMask = [.width]
        bar.addSubview(dimsLbl)
        bottomDimsLabel = dimsLbl

        let sizeLbl = NSTextField(labelWithString: sizeFormatString(for: info))
        sizeLbl.textColor = Self.textOnDarkSecondary
        sizeLbl.font = NSFont.systemFont(ofSize: 11)
        sizeLbl.lineBreakMode = .byTruncatingTail
        sizeLbl.maximumNumberOfLines = 1
        sizeLbl.frame = NSRect(x: 16, y: 10, width: width - 32, height: 14)
        sizeLbl.autoresizingMask = [.width]
        bar.addSubview(sizeLbl)
        bottomSizeLabel = sizeLbl

        return bar
    }

    private func updateSingleCardLabels(info: MediaInfo) {
        singleHeaderTitle?.stringValue = info.filename
        topPillLabel?.stringValue = info.filename
        metaPillFilename?.stringValue = info.filename
        metaPillMeta?.stringValue = metaLineString(for: info)
        bottomFilenameLabel?.stringValue = info.filename
        bottomDimsLabel?.stringValue = dimsString(for: info)
        bottomSizeLabel?.stringValue = sizeFormatString(for: info)
    }

    // MARK: - Strings

    private func dimsString(for info: MediaInfo) -> String {
        if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
            return "\(Int(dim.width)) × \(Int(dim.height))"
        }
        return info.isLocal ? "—" : ""
    }

    private func sizeFormatString(for info: MediaInfo) -> String {
        var parts: [String] = []
        if let bytes = info.fileSize {
            let f = ByteCountFormatter()
            f.countStyle = .file
            parts.append(f.string(fromByteCount: bytes))
        }
        if !info.formatName.isEmpty {
            parts.append(info.formatName)
        }
        if info.isVideo, let dur = info.duration {
            let total = Int(dur.rounded())
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        return parts.joined(separator: " • ")
    }

    private func metaLineString(for info: MediaInfo) -> String {
        var parts: [String] = []
        if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
            parts.append("\(Int(dim.width)) × \(Int(dim.height))")
        }
        if let bytes = info.fileSize {
            let f = ByteCountFormatter()
            f.countStyle = .file
            parts.append(f.string(fromByteCount: bytes))
        }
        if !info.formatName.isEmpty {
            parts.append(info.formatName)
        }
        return parts.joined(separator: " • ")
    }

    @objc private func closeButtonTapped() {
        forceHidePanel()
    }

    @objc private func actionButtonTapped() {
        if currentMode == .singleCard {
            togglePin()
            return
        }
        guard let first = currentInfos.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([first.url])
    }

    private func togglePin() {
        isPinned.toggle()
        animatePinTransition()
        singleCloseBtn?.isHidden = !isPinned
    }

    private func animatePinTransition() {
        guard let btn = singlePinBtn, let lyr = btn.layer else { return }

        // Rotate around the button's center.
        if lyr.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            lyr.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            lyr.position = CGPoint(x: btn.frame.midX, y: btn.frame.midY)
        }

        let angle: CGFloat = isPinned ? (.pi / 4) : 0   // +45° = counter-clockwise (left)
        let rot = CABasicAnimation(keyPath: "transform.rotation.z")
        rot.fromValue = lyr.value(forKeyPath: "transform.rotation.z")
        rot.toValue = angle
        rot.duration = 0.22
        rot.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rot.fillMode = .forwards
        rot.isRemovedOnCompletion = false
        lyr.add(rot, forKey: "rotate")
        lyr.setValue(angle, forKeyPath: "transform.rotation.z")

        btn.contentTintColor = isPinned ? .systemRed : Self.textDark
    }

    // MARK: - Relayout

    private func relayoutSingleCard(with media: LoadedMedia) {
        guard let tile = tiles.first, let container = contentView else { return }
        let raw = media.naturalSize
        let maxSize = Preferences.shared.maxPreviewSize
        var dw: CGFloat
        var dh: CGFloat
        if raw.width <= 0 || raw.height <= 0 {
            dw = 360; dh = 270
        } else if raw.width >= raw.height {
            dw = min(raw.width, maxSize)
            dh = dw * (raw.height / raw.width)
        } else {
            dh = min(raw.height, maxSize)
            dw = dh * (raw.width / raw.height)
        }
        dw = max(280, dw)
        dh = max(180, dh)

        let totalWidth = dw
        let totalHeight = headerHeight + dh

        container.frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)

        // Resize header (top) and image tile (full-bleed below header).
        for sv in container.subviews {
            if sv === tile {
                sv.frame = NSRect(x: 0, y: 0, width: totalWidth, height: dh)
            } else {
                // Header bar.
                sv.frame = NSRect(x: 0, y: totalHeight - headerHeight,
                                  width: totalWidth, height: headerHeight)
                relayoutHeaderBar(sv, width: totalWidth)
            }
        }
        tile.relayoutChildren()
        relayoutPanel(contentSize: NSSize(width: totalWidth, height: totalHeight))
    }

    private func relayoutHeaderBar(_ bar: NSView, width: CGFloat) {
        for sv in bar.subviews {
            switch sv.tag {
            case 1: sv.frame = NSRect(x: 12, y: (headerHeight - 24) / 2, width: 24, height: 24)
            case 2: sv.frame = NSRect(x: width - 36, y: (headerHeight - 24) / 2, width: 24, height: 24)
            case 3: sv.frame = NSRect(x: 48, y: (headerHeight - 18) / 2,
                                       width: width - 96, height: 18)
            default: sv.frame = NSRect(x: 0, y: 0, width: width, height: 1)
            }
        }
    }

    private func relayoutPanel(contentSize: NSSize) {
        let frame = ScreenManager.shared.adjustedFrame(for: contentSize, at: anchorPoint, offset: anchorOffset)
        setFrame(frame, display: true)
    }

    private func teardownTiles() {
        for tile in tiles { tile.teardown() }
        tiles.removeAll()
        currentInfos.removeAll()
        singleHeaderTitle = nil
        singleCloseBtn = nil
        singlePinBtn = nil
        bottomFilenameLabel = nil
        bottomDimsLabel = nil
        bottomSizeLabel = nil
        topPillLabel = nil
        metaPillFilename = nil
        metaPillMeta = nil
    }
}

// MARK: - Tile view

private final class MediaTileView: NSView {
    enum Style { case singleCard, masonry }

    var info: MediaInfo
    let style: Style

    private let mediaContainer = NSView()
    private let imageLayer = CALayer()
    private let spinner = NSProgressIndicator()
    private let loadingLabel = NSTextField(labelWithString: "Loading…")
    private let shimmerLayer = CAGradientLayer()

    // Masonry overlay
    private let overlayGradient = CAGradientLayer()
    private var filenameLabel: NSTextField?
    private var dimsLabel: NSTextField?
    private var sizeLabel: NSTextField?

    private var playerView: AVPlayerView?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    var onClose: (() -> Void)?
    var onAction: (() -> Void)?

    init(info: MediaInfo, style: Style, frame: NSRect) {
        self.info = info
        self.style = style
        super.init(frame: frame)
        wantsLayer = true

        switch style {
        case .singleCard:
            layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor

            mediaContainer.wantsLayer = true
            mediaContainer.layer?.masksToBounds = true
            mediaContainer.layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
            addSubview(mediaContainer)

            imageLayer.contentsGravity = .resizeAspect
            imageLayer.masksToBounds = true
            mediaContainer.layer?.addSublayer(imageLayer)

            // Bottom dark gradient + filename/dims/size labels overlaid on the image.
            overlayGradient.colors = [
                NSColor(white: 0, alpha: 0.85).cgColor,
                NSColor(white: 0, alpha: 0.45).cgColor,
                NSColor(white: 0, alpha: 0.0).cgColor
            ]
            overlayGradient.locations = [0.0, 0.55, 1.0]
            overlayGradient.startPoint = CGPoint(x: 0.5, y: 0)
            overlayGradient.endPoint = CGPoint(x: 0.5, y: 1)
            mediaContainer.layer?.addSublayer(overlayGradient)

            let nameLbl = NSTextField(labelWithString: info.filename)
            nameLbl.textColor = .white
            nameLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            nameLbl.lineBreakMode = .byTruncatingMiddle
            nameLbl.maximumNumberOfLines = 1
            addSubview(nameLbl)
            filenameLabel = nameLbl

            let dimsLbl = NSTextField(labelWithString: "")
            dimsLbl.textColor = NSColor(white: 1, alpha: 0.85)
            dimsLbl.font = NSFont.systemFont(ofSize: 11)
            dimsLbl.lineBreakMode = .byTruncatingTail
            dimsLbl.maximumNumberOfLines = 1
            addSubview(dimsLbl)
            dimsLabel = dimsLbl

            let sizeLbl = NSTextField(labelWithString: "")
            sizeLbl.textColor = NSColor(white: 1, alpha: 0.85)
            sizeLbl.font = NSFont.systemFont(ofSize: 11)
            sizeLbl.lineBreakMode = .byTruncatingTail
            sizeLbl.maximumNumberOfLines = 1
            addSubview(sizeLbl)
            sizeLabel = sizeLbl

        case .masonry:
            // Image fills the entire card; text overlay sits in the top-left.
            layer?.cornerRadius = 8
            layer?.masksToBounds = true
            layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor

            mediaContainer.wantsLayer = true
            mediaContainer.layer?.masksToBounds = true
            mediaContainer.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
            addSubview(mediaContainer)

            // Animated shimmer band — moves left→right while the image is loading.
            shimmerLayer.colors = [
                NSColor(white: 1, alpha: 0).cgColor,
                NSColor(white: 1, alpha: 0.10).cgColor,
                NSColor(white: 1, alpha: 0).cgColor
            ]
            shimmerLayer.locations = [0.0, 0.5, 1.0]
            shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
            shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
            mediaContainer.layer?.addSublayer(shimmerLayer)
            startShimmer()

            imageLayer.contentsGravity = .resizeAspectFill
            imageLayer.masksToBounds = true
            mediaContainer.layer?.addSublayer(imageLayer)

            // Dark gradient on the bottom edge so the white text overlay is readable.
            // Must live above the image layer (same container) and below the text NSTextFields.
            overlayGradient.colors = [
                NSColor(white: 0, alpha: 0.88).cgColor,
                NSColor(white: 0, alpha: 0.55).cgColor,
                NSColor(white: 0, alpha: 0.0).cgColor
            ]
            overlayGradient.locations = [0.0, 0.55, 1.0]
            overlayGradient.startPoint = CGPoint(x: 0.5, y: 0)
            overlayGradient.endPoint = CGPoint(x: 0.5, y: 1)
            mediaContainer.layer?.addSublayer(overlayGradient)

            let nameLbl = NSTextField(labelWithString: info.filename)
            nameLbl.textColor = .white
            nameLbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            nameLbl.lineBreakMode = .byTruncatingMiddle
            nameLbl.maximumNumberOfLines = 1
            addSubview(nameLbl)
            filenameLabel = nameLbl

            let dimsLbl = NSTextField(labelWithString: "")
            dimsLbl.textColor = NSColor(white: 1, alpha: 0.95)
            dimsLbl.font = NSFont.systemFont(ofSize: 10)
            dimsLbl.lineBreakMode = .byTruncatingTail
            dimsLbl.maximumNumberOfLines = 1
            addSubview(dimsLbl)
            dimsLabel = dimsLbl

            let sizeLbl = NSTextField(labelWithString: "")
            sizeLbl.textColor = NSColor(white: 1, alpha: 0.95)
            sizeLbl.font = NSFont.systemFont(ofSize: 10)
            sizeLbl.lineBreakMode = .byTruncatingTail
            sizeLbl.maximumNumberOfLines = 1
            addSubview(sizeLbl)
            sizeLabel = sizeLbl
        }

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.usesThreadedAnimation = true
        spinner.appearance = NSAppearance(named: .vibrantDark)
        spinner.startAnimation(nil)
        addSubview(spinner)

        loadingLabel.textColor = NSColor(white: 1, alpha: 0.85)
        loadingLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        loadingLabel.alignment = .center
        loadingLabel.maximumNumberOfLines = 1
        addSubview(loadingLabel)

        relayoutChildren()
    }

    private func startShimmer() {
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-0.5, 0.0, 0.5]
        anim.toValue   = [0.5, 1.0, 1.5]
        anim.duration = 1.2
        anim.repeatCount = .infinity
        shimmerLayer.add(anim, forKey: "shimmer")
    }

    private func stopShimmer() {
        shimmerLayer.removeAnimation(forKey: "shimmer")
        shimmerLayer.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func relayoutChildren() {
        let spinnerSize: CGFloat = 20
        switch style {
        case .singleCard:
            mediaContainer.frame = bounds
            imageLayer.frame = mediaContainer.bounds
            playerView?.frame = mediaContainer.bounds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let gradH: CGFloat = 76
            overlayGradient.frame = NSRect(x: 0, y: 0, width: bounds.width, height: gradH)
            CATransaction.commit()
            spinner.frame = NSRect(
                x: bounds.midX - spinnerSize / 2,
                y: bounds.midY - spinnerSize / 2 + 8,
                width: spinnerSize, height: spinnerSize
            )
            loadingLabel.frame = NSRect(x: 0, y: bounds.midY - 18,
                                         width: bounds.width, height: 14)
            let textX: CGFloat = 14
            let textW = bounds.width - textX - 14
            filenameLabel?.frame = NSRect(x: textX, y: 50, width: textW, height: 16)
            dimsLabel?.frame     = NSRect(x: textX, y: 30, width: textW, height: 14)
            sizeLabel?.frame     = NSRect(x: textX, y: 10, width: textW, height: 14)

        case .masonry:
            mediaContainer.frame = bounds
            imageLayer.frame = mediaContainer.bounds
            playerView?.frame = mediaContainer.bounds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let gradientH: CGFloat = 60
            overlayGradient.frame = NSRect(x: 0, y: 0, width: bounds.width, height: gradientH)
            shimmerLayer.frame = mediaContainer.bounds
            CATransaction.commit()
            spinner.frame = NSRect(
                x: bounds.midX - spinnerSize / 2,
                y: bounds.midY - spinnerSize / 2 + 6,
                width: spinnerSize, height: spinnerSize
            )
            loadingLabel.frame = NSRect(x: 0, y: bounds.midY - 18,
                                         width: bounds.width, height: 14)

            let textX: CGFloat = 8
            let textW = bounds.width - textX - 8
            filenameLabel?.frame = NSRect(x: textX, y: 40, width: textW, height: 14)
            dimsLabel?.frame     = NSRect(x: textX, y: 24, width: textW, height: 12)
            sizeLabel?.frame     = NSRect(x: textX, y: 8,  width: textW, height: 12)
        }
    }

    func setLoaded(_ media: LoadedMedia) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        loadingLabel.isHidden = true
        stopShimmer()

        switch media {
        case .image(let img, let info):
            imageLayer.contents = img
            updateText(with: info)
        case .video(let url, _, let info):
            attachPlayer(url: url)
            updateText(with: info)
        }
    }

    func setFailed() {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        loadingLabel.stringValue = "Failed"
        loadingLabel.textColor = .systemRed
        stopShimmer()
        if style == .masonry {
            dimsLabel?.stringValue = "Failed to load"
            dimsLabel?.textColor = .systemRed
        }
    }

    func updateInfo(_ newInfo: MediaInfo) {
        self.info = newInfo
        updateText(with: newInfo)
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

    private func updateText(with info: MediaInfo) {
        filenameLabel?.stringValue = info.filename

        if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
            dimsLabel?.stringValue = "\(Int(dim.width)) × \(Int(dim.height))"
        } else {
            dimsLabel?.stringValue = info.isLocal ? "—" : ""
        }

        if let bytes = info.fileSize {
            let f = ByteCountFormatter()
            f.countStyle = .file
            var parts = [f.string(fromByteCount: bytes)]
            if !info.formatName.isEmpty { parts.append(info.formatName) }
            sizeLabel?.stringValue = parts.joined(separator: " • ")
        } else {
            sizeLabel?.stringValue = info.formatName
        }
    }
}
