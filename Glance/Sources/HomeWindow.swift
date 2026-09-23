import AppKit

/// Glance's launcher / home window.
///
/// Glance normally opens from a selection carrier (image / video / file via the
/// global hotkey). This window is the only entry point that lets the user start
/// from nothing: drop images or a folder, pick files or a folder, or reopen a
/// recent item. Choosing a folder reads every image inside it and hands them to
/// Image Inspect as one filmstrip.
///
/// The window uses native 1:1 point coordinates (no design-scale factor) so
/// text renders crisply and never clips. Chrome mirrors the Figma "Home /
/// Launcher" frame: a dark titlebar with custom traffic lights, an icon
/// toolbar, a left "open surface" with a dashed drop zone, and a right "Recent"
/// column reusing `MediaTileView`.
final class HomeWindow: NSWindow, NSWindowDelegate {
    // MARK: Callbacks (wired by AppDelegate)

    var onOpenImages: (([URL]) -> Void)?
    var onOpenMedia: (([URL]) -> Void)?
    var onOpenFolder: ((URL) -> Void)?
    var onOpenRecent: ((MediaInfo) -> Void)?
    var onOpenTasks: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    // MARK: Geometry (native points)

    private enum Metric {
        static let titlebarH: CGFloat = 52
        static let statusH: CGFloat = 30
        static let recentWidth: CGFloat = 380
        static let pad: CGFloat = 40
        static let recentTile = NSSize(width: 168, height: 148)
        static let recentSpacing: CGFloat = 16
    }

    private static let contentSize = NSSize(width: 1080, height: 720)

    private let imageLoader: ImageLoader
    private let pathDetector = PathDetector()

    // MARK: Views

    private let contentContainer = DropContainerView()
    private let titlebar = HomeTitlebar()
    private let windowTitleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let openSurface = HomeFlippedView()
    private let recentColumn = HomeFlippedView()
    private let statusbar = NSView()
    private let leftStatusLabel = NSTextField(labelWithString: "")
    private let centerHintLabel = NSTextField(labelWithString: "")

    private lazy var closeTrafficButton = HomeTrafficLightButton(
        color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1),
        target: self, action: #selector(closeTapped))
    private lazy var minimizeTrafficButton = HomeTrafficLightButton(
        color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1),
        target: self, action: #selector(minimizeTapped))
    private lazy var zoomTrafficButton = HomeTrafficLightButton(
        color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1),
        target: self, action: #selector(zoomTapped))

    // Open surface
    private let welcomeLabel = NSTextField(labelWithString: "")
    private let welcomeSubLabel = NSTextField(wrappingLabelWithString: "")
    private let dropZone = DropZoneView()
    private let dropIconView = NSImageView()
    private let dropTitleLabel = NSTextField(labelWithString: "")
    private let dropHintLabel = NSTextField(labelWithString: "")
    private lazy var openFilesButton = PanelStyle.makePrimaryButton(
        title: "Open Files…".localized, target: self, action: #selector(openFilesTapped))
    private lazy var openFolderButton = PanelStyle.makeQuietButton(
        title: "Open Folder…".localized, target: self, action: #selector(openFolderTapped))

    // Folder-loaded state
    private let folderGroupLabel = NSTextField(labelWithString: "")
    private let folderCountLabel = NSTextField(labelWithString: "")
    private let folderStrip = NSView()
    private let inspectAllButton: PanelButton
    private var folderImageURLs: [URL] = []
    private var folderThumbViews: [NSView] = []

    // Recent
    private let recentHeadingLabel = NSTextField(labelWithString: "")
    private let recentSubLabel = NSTextField(labelWithString: "")
    private let recentEmptyLabel = NSTextField(labelWithString: "")
    private let recentScroll = NSScrollView()
    private let recentDocView = HomeFlippedView()
    private var recentCards: [RecentCardView] = []

    // MARK: Init

    init(imageLoader: ImageLoader) {
        self.imageLoader = imageLoader
        self.inspectAllButton = PanelStyle.makePrimaryButton(title: "", target: nil, action: nil)
        super.init(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        delegate = self
        title = "Glance".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = PanelStyle.inspectBackground
        isMovableByWindowBackground = false
        minSize = NSSize(width: 900, height: 560)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        registerForDraggedTypes([.fileURL])

        buildUI()
        refresh()

        NotificationCenter.default.addObserver(
            self, selector: #selector(languageChanged),
            name: .languageDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(historyChanged),
            name: HistoryManager.didChange, object: nil)

        setFrame(ScreenManager.shared.contentFrame(for: Self.contentSize), display: false)
        layoutContent()
        // The content view's bounds settle after the frame is applied; lay out
        // once more on the next turn so the recent grid builds at its real size.
        DispatchQueue.main.async { [weak self] in self?.layoutContent() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Build

    private func buildUI() {
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectBackground)
        contentContainer.onFilesDropped = { [weak self] urls in self?.handleDroppedURLs(urls) }
        contentView = contentContainer

        // Titlebar
        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        contentContainer.addSubview(titlebar)
        configureLabel(windowTitleLabel, size: 15, weight: .semibold, color: PanelStyle.textPrimary, align: .center)
        windowTitleLabel.stringValue = "Glance".localized
        titlebar.addSubview(windowTitleLabel)
        configureLabel(subtitleLabel, size: 11, color: PanelStyle.textTertiary, align: .center)
        subtitleLabel.stringValue = "Open media to inspect".localized
        titlebar.addSubview(subtitleLabel)
        titlebar.addSubview(closeTrafficButton)
        titlebar.addSubview(minimizeTrafficButton)
        titlebar.addSubview(zoomTrafficButton)

        // Left open surface
        openSurface.wantsLayer = true
        openSurface.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        contentContainer.addSubview(openSurface)
        buildOpenSurface()

        // Right recent column
        recentColumn.wantsLayer = true
        recentColumn.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surface)
        recentColumn.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        recentColumn.layer?.borderWidth = 1
        contentContainer.addSubview(recentColumn)
        buildRecentColumn()

        // Statusbar
        statusbar.wantsLayer = true
        statusbar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectStatus)
        statusbar.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        statusbar.layer?.borderWidth = 1
        contentContainer.addSubview(statusbar)
        configureLabel(leftStatusLabel, size: 12, color: PanelStyle.textSecondary)
        leftStatusLabel.stringValue = "No file open  •  Open images to begin".localized
        statusbar.addSubview(leftStatusLabel)
        configureLabel(centerHintLabel, size: 12, color: PanelStyle.textSecondary, align: .center)
        centerHintLabel.stringValue = "Drop files anywhere  •  ⌘O to open  •  ⌘⇧O for a folder".localized
        statusbar.addSubview(centerHintLabel)
    }

    /// Ensure every backing layer renders at the screen's native scale.
    /// A layer left at contentsScale 1.0 on a 2x display looks soft/blurry.
    private func applyBackingScale() {
        let scale = backingScaleFactor
        func apply(_ view: NSView) {
            if view.wantsLayer { view.layer?.contentsScale = scale }
            for sub in view.subviews { apply(sub) }
        }
        apply(contentContainer)
    }

    private func configureLabel(_ label: NSTextField, size: CGFloat,
                                weight: NSFont.Weight = .regular,
                                color: NSColor, align: NSTextAlignment = .left) {
        label.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = align
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
    }

    private func buildOpenSurface() {
        configureLabel(welcomeLabel, size: 22, weight: .semibold, color: PanelStyle.textPrimary)
        welcomeLabel.stringValue = "Open something to inspect".localized
        openSurface.addSubview(welcomeLabel)

        welcomeSubLabel.font = PanelStyle.inspectFont(ofSize: 13)
        welcomeSubLabel.textColor = PanelStyle.textSecondary
        welcomeSubLabel.stringValue = "Drop images or videos here, or choose files and folders.".localized
        welcomeSubLabel.maximumNumberOfLines = 2
        welcomeSubLabel.lineBreakMode = .byWordWrapping
        openSurface.addSubview(welcomeSubLabel)

        dropZone.onFilesDropped = { [weak self] urls in self?.handleDroppedURLs(urls) }
        openSurface.addSubview(dropZone)

        dropIconView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        dropIconView.contentTintColor = PanelStyle.accent
        dropIconView.imageScaling = .scaleProportionallyUpOrDown
        dropZone.addSubview(dropIconView)

        configureLabel(dropTitleLabel, size: 16, weight: .semibold, color: PanelStyle.textPrimary, align: .center)
        dropTitleLabel.stringValue = "Drag images, videos or a folder here".localized
        dropZone.addSubview(dropTitleLabel)

        configureLabel(dropHintLabel, size: 11, color: PanelStyle.textTertiary, align: .center)
        dropHintLabel.stringValue = "PNG · JPEG · HEIC · WebP · MP4 · MOV · WebM  and more".localized
        dropZone.addSubview(dropHintLabel)

        openSurface.addSubview(openFilesButton)
        openSurface.addSubview(openFolderButton)

        configureLabel(folderGroupLabel, size: 11, weight: .semibold, color: PanelStyle.textTertiary)
        openSurface.addSubview(folderGroupLabel)
        configureLabel(folderCountLabel, size: 11, color: PanelStyle.textSecondary, align: .right)
        openSurface.addSubview(folderCountLabel)

        folderStrip.wantsLayer = true
        folderStrip.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surface)
        folderStrip.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        folderStrip.layer?.borderWidth = 1
        folderStrip.layer?.cornerRadius = 12
        openSurface.addSubview(folderStrip)

        inspectAllButton.target = self
        inspectAllButton.action = #selector(inspectAllTapped)
        openSurface.addSubview(inspectAllButton)

        setFolderStateHidden(true)
    }

    private func buildRecentColumn() {
        configureLabel(recentHeadingLabel, size: 19, weight: .semibold, color: PanelStyle.textPrimary)
        recentHeadingLabel.stringValue = "Recent".localized
        recentColumn.addSubview(recentHeadingLabel)

        configureLabel(recentSubLabel, size: 11, color: PanelStyle.textTertiary)
        recentSubLabel.stringValue = "Reopen what you inspected before.".localized
        recentColumn.addSubview(recentSubLabel)

        configureLabel(recentEmptyLabel, size: 12, color: PanelStyle.textTertiary, align: .center)
        recentEmptyLabel.stringValue = "Nothing here yet. Inspected files show up here.".localized
        recentEmptyLabel.isHidden = true
        recentColumn.addSubview(recentEmptyLabel)

        recentScroll.drawsBackground = false
        recentScroll.hasVerticalScroller = false
        recentScroll.hasHorizontalScroller = false
        recentScroll.autohidesScrollers = true
        recentScroll.verticalScrollElasticity = .allowed
        recentScroll.scrollerStyle = .overlay
        recentScroll.documentView = recentDocView
        recentColumn.addSubview(recentScroll)
    }

    // MARK: Layout

    private func layoutContent() {
        let W = contentContainer.bounds.width
        let H = contentContainer.bounds.height
        guard W > 0, H > 0 else { return }
        applyBackingScale()

        // Titlebar
        titlebar.frame = NSRect(x: 0, y: H - Metric.titlebarH, width: W, height: Metric.titlebarH)
        let dot: CGFloat = 12
        let dotY = (Metric.titlebarH - dot) / 2
        closeTrafficButton.frame = NSRect(x: 20, y: dotY, width: dot, height: dot)
        minimizeTrafficButton.frame = NSRect(x: 40, y: dotY, width: dot, height: dot)
        zoomTrafficButton.frame = NSRect(x: 60, y: dotY, width: dot, height: dot)
        // Title + subtitle stacked, vertically centered in the titlebar.
        windowTitleLabel.frame = NSRect(x: 100, y: Metric.titlebarH / 2, width: W - 200, height: 20)
        subtitleLabel.frame = NSRect(x: 100, y: Metric.titlebarH / 2 - 17, width: W - 200, height: 14)

        // Statusbar
        statusbar.frame = NSRect(x: 0, y: 0, width: W, height: Metric.statusH)
        leftStatusLabel.frame = NSRect(x: 20, y: (Metric.statusH - 15) / 2, width: 460, height: 15)
        centerHintLabel.frame = NSRect(x: 0, y: (Metric.statusH - 15) / 2, width: W, height: 15)

        // Body
        let bodyTop = H - Metric.titlebarH
        let bodyH = bodyTop - Metric.statusH
        let openW = W - Metric.recentWidth
        openSurface.frame = NSRect(x: 0, y: Metric.statusH, width: openW, height: bodyH)
        recentColumn.frame = NSRect(x: openW, y: Metric.statusH, width: Metric.recentWidth, height: bodyH)

        layoutOpenSurface()
        layoutRecentColumn()
    }

    private func layoutOpenSurface() {
        // Flipped view: y grows downward from the top.
        let w = openSurface.bounds.width
        let p = Metric.pad
        let contentW = w - p * 2

        welcomeLabel.frame = NSRect(x: p, y: 40, width: contentW, height: 34)
        welcomeSubLabel.frame = NSRect(x: p, y: 82, width: min(contentW, 620), height: 40)

        let dropW = contentW
        let dropH: CGFloat = 260
        dropZone.frame = NSRect(x: p, y: 128, width: dropW, height: dropH)
        dropIconView.frame = NSRect(x: (dropW - 40) / 2, y: 62, width: 40, height: 40)
        dropTitleLabel.frame = NSRect(x: 0, y: 140, width: dropW, height: 22)
        dropHintLabel.frame = NSRect(x: 0, y: 170, width: dropW, height: 15)

        let btnY = 128 + dropH + 20
        openFilesButton.frame = NSRect(x: p, y: btnY, width: 150, height: 36)
        openFolderButton.frame = NSRect(x: p + 162, y: btnY, width: 150, height: 36)

        let folderY = btnY + 36 + 30
        folderGroupLabel.frame = NSRect(x: p, y: folderY, width: contentW - 120, height: 15)
        folderCountLabel.frame = NSRect(x: p + contentW - 160, y: folderY, width: 160, height: 15)
        let stripY = folderY + 26
        folderStrip.frame = NSRect(x: p, y: stripY, width: contentW, height: 108)
        inspectAllButton.frame = NSRect(x: p, y: stripY + 108 + 16, width: 220, height: 36)
        layoutFolderStrip()

        // Grow the flipped content view so scrolling isn't needed here.
        let neededH = inspectAllButton.frame.maxY + 24
        if openSurface.frame.height < neededH {
            // Only used if window is very short; keep simple, no scroll.
        }
    }

    private func layoutRecentColumn() {
        // recentColumn is a flipped view: y grows downward from the top.
        let w = recentColumn.bounds.width
        let h = recentColumn.bounds.height
        let p = Metric.pad
        recentHeadingLabel.frame = NSRect(x: p, y: 40, width: w - p * 2, height: 28)
        recentSubLabel.frame = NSRect(x: p, y: 72, width: w - p * 2, height: 16)

        // The tile grid sits BELOW the "Reopen…" caption.
        let gridTop: CGFloat = 104
        recentScroll.frame = NSRect(x: 20, y: gridTop, width: max(0, w - 40), height: max(0, h - gridTop - 16))
        recentEmptyLabel.frame = NSRect(x: 0, y: gridTop + 40, width: w, height: 20)
        relayoutRecentTiles()
    }

    /// Fixed 2-column grid, tiles sized to the available width.
    private static let recentColumns = 2

    // MARK: Recent tiles

    func refresh() { rebuildRecent() }

    private func rebuildRecent() {
        for card in recentCards { card.removeFromSuperview() }
        recentCards.removeAll()

        var seen = Set<String>()
        let infos: [MediaInfo] = HistoryManager.shared.records
            .flatMap { $0.items }
            .filter { seen.insert($0.value).inserted }
            .compactMap { $0.detectedPath }
            .compactMap { MediaInfo.from($0) }

        recentEmptyLabel.isHidden = !infos.isEmpty
        for info in infos {
            let card = RecentCardView(info: info)
            let captured = info
            card.onTap = { [weak self] in self?.onOpenRecent?(captured) }
            recentDocView.addSubview(card)
            recentCards.append(card)
            loadThumbnail(for: info, card: card)
        }
        relayoutRecentTiles()
    }

    private func relayoutRecentTiles() {
        var contentW = recentScroll.contentSize.width
        if contentW <= 0 { contentW = recentScroll.frame.width }
        guard contentW > 0 else { return }

        let cols = Self.recentColumns
        let spacing = Metric.recentSpacing
        let tileW = ((contentW - CGFloat(cols - 1) * spacing) / CGFloat(cols)).rounded(.down)
        let tileH = (tileW * 0.92).rounded()

        for (idx, card) in recentCards.enumerated() {
            let row = idx / cols
            let col = idx % cols
            let x = (CGFloat(col) * (tileW + spacing)).rounded()
            let y = (CGFloat(row) * (tileH + spacing)).rounded()
            card.frame = NSRect(x: x, y: y, width: tileW, height: tileH)
        }

        let rows = (recentCards.count + cols - 1) / cols
        let docH = max(CGFloat(rows) * (tileH + spacing), recentScroll.contentSize.height)
        recentDocView.frame = NSRect(x: 0, y: 0, width: contentW, height: docH)
    }

    private func loadThumbnail(for info: MediaInfo, card: RecentCardView) {
        switch info.kind {
        case .image:
            imageLoader.loadImage(from: info.url) { [weak card] image in
                DispatchQueue.main.async {
                    if let image = image { card?.setImage(image) } else { card?.setFailed() }
                }
            }
        default:
            card.setPlaceholder(for: info)
        }
    }

    // MARK: Folder strip

    private func setFolderStateHidden(_ hidden: Bool) {
        folderGroupLabel.isHidden = hidden
        folderCountLabel.isHidden = hidden
        folderStrip.isHidden = hidden
        inspectAllButton.isHidden = hidden
    }

    func showFolder(_ folder: URL, imageURLs: [URL]) {
        folderImageURLs = imageURLs
        folderGroupLabel.stringValue = "FOLDER".localized + "  ·  " + folder.abbreviatedDisplayPath
        folderCountLabel.stringValue = String(format: "%d images found".localized, imageURLs.count)
        inspectAllButton.title = String(format: "Inspect all %d images".localized, imageURLs.count)
        setFolderStateHidden(imageURLs.isEmpty)
        leftStatusLabel.stringValue = imageURLs.isEmpty
            ? "No images in that folder".localized
            : String(format: "%d images ready".localized, imageURLs.count)
        rebuildFolderStrip()
        layoutOpenSurface()
    }

    private func rebuildFolderStrip() {
        for v in folderThumbViews { v.removeFromSuperview() }
        folderThumbViews.removeAll()
        let maxThumbs = 8
        for url in folderImageURLs.prefix(maxThumbs) {
            let thumb = NSImageView()
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 6
            thumb.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
            thumb.layer?.borderWidth = 1
            thumb.layer?.masksToBounds = true
            thumb.imageScaling = .scaleAxesIndependently
            thumb.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surfaceRaised)
            folderStrip.addSubview(thumb)
            folderThumbViews.append(thumb)
            imageLoader.loadImage(from: url) { [weak thumb] image in
                DispatchQueue.main.async { if let image = image { thumb?.image = image } }
            }
        }
        if folderImageURLs.count > maxThumbs {
            let more = NSTextField(labelWithString: "+\(folderImageURLs.count - maxThumbs)")
            more.font = PanelStyle.inspectFont(ofSize: 15, weight: .semibold)
            more.textColor = PanelStyle.textSecondary
            more.alignment = .center
            more.wantsLayer = true
            more.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surfaceRaised)
            more.layer?.cornerRadius = 6
            more.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
            more.layer?.borderWidth = 1
            folderStrip.addSubview(more)
            folderThumbViews.append(more)
        }
        layoutFolderStrip()
    }

    private func layoutFolderStrip() {
        let thumb: CGFloat = 84
        let pitch: CGFloat = 96
        let y = (folderStrip.bounds.height - thumb) / 2
        for (i, v) in folderThumbViews.enumerated() {
            let x = 12 + CGFloat(i) * pitch
            if let field = v as? NSTextField {
                field.frame = NSRect(x: x, y: y + (thumb - 20) / 2, width: thumb, height: 20)
            } else {
                v.frame = NSRect(x: x, y: y, width: thumb, height: thumb)
            }
        }
    }

    // MARK: Actions

    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }
    @objc private func tasksTapped() { onOpenTasks?() }
    @objc private func preferencesTapped() { onOpenPreferences?() }
    @objc private func aboutTapped() { NSApp.orderFrontStandardAboutPanel(nil) }

    @objc private func openFilesTapped() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self else { return }
            self.handleDroppedURLs(panel.urls)
        }
    }

    @objc private func openFolderTapped() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self, let url = panel.urls.first else { return }
            self.onOpenFolder?(url)
        }
    }

    @objc private func inspectAllTapped() {
        guard !folderImageURLs.isEmpty else { return }
        onOpenImages?(folderImageURLs)
    }

    private func handleDroppedURLs(_ urls: [URL]) {
        if urls.count == 1, let only = urls.first,
           case .localFolder(let folder) = pathDetector.localKind(for: only.path) {
            onOpenFolder?(folder)
            return
        }
        let media = urls.filter {
            switch pathDetector.localKind(for: $0.path) {
            case .localImage, .localVideo: return true
            default: return false
            }
        }
        if !media.isEmpty { onOpenMedia?(media) }
    }

    // MARK: Notifications

    @objc private func languageChanged() {
        windowTitleLabel.stringValue = "Glance".localized
        subtitleLabel.stringValue = "Open media to inspect".localized
        welcomeLabel.stringValue = "Open something to inspect".localized
        welcomeSubLabel.stringValue = "Drop images or videos here, or choose files and folders.".localized
        dropTitleLabel.stringValue = "Drag images, videos or a folder here".localized
        dropHintLabel.stringValue = "PNG · JPEG · HEIC · WebP · MP4 · MOV · WebM  and more".localized
        recentHeadingLabel.stringValue = "Recent".localized
        recentSubLabel.stringValue = "Reopen what you inspected before.".localized
        leftStatusLabel.stringValue = "No file open  •  Open images to begin".localized
        centerHintLabel.stringValue = "Drop files anywhere  •  ⌘O to open  •  ⌘⇧O for a folder".localized
        openFilesButton.title = "Open Files…".localized
        openFolderButton.title = "Open Folder…".localized
        layoutContent()
    }

    @objc private func historyChanged() {
        DispatchQueue.main.async { [weak self] in self?.rebuildRecent() }
    }

    func windowDidResize(_ notification: Notification) {
        layoutContent()
    }

    @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    @objc func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        handleDroppedURLs(urls)
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers {
            if chars == "o" {
                if event.modifierFlags.contains(.shift) { openFolderTapped() } else { openFilesTapped() }
                return true
            }
            if chars == "v" {
                if pasteFromClipboard() { return true }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Standard Edit-menu / responder-chain paste target.
    @objc func paste(_ sender: Any?) {
        pasteFromClipboard()
    }

    /// ⌘V: open an image sitting on the clipboard — raw image data (screenshot,
    /// browser copy), a copied file, or an image URL/path as text.
    @discardableResult
    private func pasteFromClipboard() -> Bool {
        let pb = NSPasteboard.general

        // 1) Copied file(s) — Finder "Copy" puts file URLs on the pasteboard.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            handleDroppedURLs(urls)
            return true
        }

        // 2) Raw image data (screenshot / copied bitmap) — materialize to PNG.
        if let url = Self.materializeClipboardImage() {
            onOpenImages?([url])
            return true
        }

        // 3) An image URL or local path pasted as text.
        if let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            let expanded = (text as NSString).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: expanded)
            if case .localImage = pathDetector.localKind(for: fileURL.path) {
                onOpenImages?([fileURL])
                return true
            }
            if let remote = URL(string: text), remote.scheme?.hasPrefix("http") == true {
                onOpenImages?([remote])
                return true
            }
        }
        NSSound.beep()
        return false
    }

    /// Turn raw clipboard image data into a temporary PNG file URL.
    private static func materializeClipboardImage() -> URL? {
        let pb = NSPasteboard.general
        let types: [NSPasteboard.PasteboardType] = [
            .png, .tiff,
            NSPasteboard.PasteboardType(rawValue: "public.jpeg"),
            NSPasteboard.PasteboardType(rawValue: "public.heic")
        ]
        guard let type = pb.availableType(from: types),
              let data = pb.data(forType: type),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceClipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("clipboard-\(UUID().uuidString).png")
        guard (try? png.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Supporting views

private final class HomeFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class HomeTitlebar: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
}

private final class HomeTrafficLightButton: NSButton {
    init(color: NSColor, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(color)
        self.target = target
        self.action = action
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
    }
}

/// A self-contained recent-item card: image thumbnail with filename + type
/// overlay, plus explicit loading / failed states. Independent of MediaTileView
/// so its rendering is fully predictable inside the Home grid.
private final class RecentCardView: NSView {
    var onTap: (() -> Void)?
    private let info: MediaInfo
    private let imageView = NSImageView()
    private let overlay = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let typeLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")

    init(info: MediaInfo) {
        self.info = info
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surfaceRaised)
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        layer?.borderWidth = 1

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        addSubview(imageView)

        stateLabel.font = PanelStyle.inspectFont(ofSize: 11)
        stateLabel.textColor = PanelStyle.textTertiary
        stateLabel.alignment = .center
        stateLabel.stringValue = "Loading…".localized
        stateLabel.backgroundColor = .clear
        stateLabel.isBordered = false
        stateLabel.isEditable = false
        addSubview(stateLabel)

        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        addSubview(overlay)

        nameLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = PanelStyle.textPrimary
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.cell?.usesSingleLineMode = true
        nameLabel.stringValue = info.filename
        overlay.addSubview(nameLabel)

        typeLabel.font = PanelStyle.inspectFont(ofSize: 10)
        typeLabel.textColor = PanelStyle.textTertiary
        typeLabel.alignment = .right
        typeLabel.stringValue = info.formatName
        overlay.addSubview(typeLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: NSImage) {
        imageView.image = image
        stateLabel.isHidden = true
    }

    func setFailed() {
        imageView.image = nil
        stateLabel.stringValue = "Failed to load".localized
        stateLabel.textColor = PanelStyle.danger
        stateLabel.isHidden = false
    }

    func setPlaceholder(for info: MediaInfo) {
        let symbol: String
        switch info.kind {
        case .video: symbol = "film"
        case .markdown, .text: symbol = "doc.text"
        case .pdf: symbol = "doc.richtext"
        case .webPage: symbol = "globe"
        case .folder: symbol = "folder"
        default: symbol = "doc"
        }
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageView.contentTintColor = PanelStyle.textTertiary
        imageView.imageScaling = .scaleNone
        stateLabel.isHidden = true
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        let overlayH: CGFloat = 34
        overlay.frame = NSRect(x: 0, y: 0, width: bounds.width, height: overlayH)
        nameLabel.frame = NSRect(x: 12, y: (overlayH - 16) / 2, width: bounds.width - 60, height: 16)
        typeLabel.frame = NSRect(x: bounds.width - 52, y: (overlayH - 14) / 2, width: 40, height: 14)
        stateLabel.frame = NSRect(x: 0, y: bounds.midY - 8, width: bounds.width, height: 16)
    }

    override func mouseDown(with event: NSEvent) { onTap?() }
}

private final class DropZoneView: NSView {
    var onFilesDropped: (([URL]) -> Void)?
    private var isTargeted = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: inset, xRadius: 16, yRadius: 16)
        path.lineWidth = 2
        let color = isTargeted ? PanelStyle.accentHover : PanelStyle.accent.withAlphaComponent(0.5)
        color.setStroke()
        path.setLineDash([8, 6], count: 2, phase: 0)
        path.stroke()
        if isTargeted {
            PanelStyle.accent.withAlphaComponent(0.06).setFill()
            let fillPath = NSBezierPath(roundedRect: inset, xRadius: 16, yRadius: 16)
            fillPath.fill()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { isTargeted = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { isTargeted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        guard let items = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !items.isEmpty else { return false }
        onFilesDropped?(items)
        return true
    }
}

private final class DropContainerView: NSView {
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !items.isEmpty else { return false }
        onFilesDropped?(items)
        return true
    }
}

private extension URL {
    var abbreviatedDisplayPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
