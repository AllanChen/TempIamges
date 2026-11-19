import AppKit

/// Glance's launcher / home window.
///
/// Glance normally opens from a selection carrier (image / video / file via the
/// global hotkey). This window is the only entry point that lets the user start
/// from nothing: drop images or a folder, pick files or a folder, or reopen a
/// recent item. Choosing a folder reads every image inside it and hands them to
/// Image Inspect as one filmstrip.
///
/// Layout follows the Shizuka Figma frames `02 · Home`, `46 · Home / Folder
/// loaded` and `47 · Empty states`: one ink-1 surface, a 44pt titlebar, a main
/// column centered in the left area, a 1px divider, a 312pt "Recent" list and a
/// 32pt status bar. Every container is flipped so Figma's top-origin
/// coordinates map 1:1 onto frames.
final class HomeWindow: NSWindow, NSWindowDelegate {
    // MARK: Callbacks (wired by AppDelegate)

    var onOpenImages: (([URL]) -> Void)?
    var onOpenMedia: (([URL]) -> Void)?
    var onOpenFolder: ((URL) -> Void)?
    var onOpenRecent: ((MediaInfo) -> Void)?
    var onOpenTasks: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    // MARK: Geometry (Figma points)

    private enum Metric {
        static let titlebarH: CGFloat = 44
        static let statusH: CGFloat = 32
        /// Divider to the window's right edge (1440 − 1080).
        static let recentWidth: CGFloat = 360
        /// Recent list inset from the divider / right edge, and its width.
        static let recentInset: CGFloat = 24
        static let recentListW: CGFloat = 312
        static let mainMaxW: CGFloat = 856
        static let mainMinPad: CGFloat = 40
        static let rowH: CGFloat = 56
        static let rowPitch: CGFloat = 58
        static let gridTile: CGFloat = 132
        static let gridGap: CGFloat = 12
        static let dropMaxH: CGFloat = 300
        static let dropMinH: CGFloat = 160
    }

    private static let contentSize = NSSize(width: 1080, height: 720)
    private static let savedSizeKey = "HomeWindowUserSize"

    private static var openingSize: NSSize {
        guard let saved = UserDefaults.standard.dictionary(forKey: savedSizeKey),
              let width = saved["width"] as? Double,
              let height = saved["height"] as? Double,
              width.isFinite, height.isFinite, width >= 900, height >= 580 else {
            return contentSize
        }
        return NSSize(width: width, height: height)
    }

    private let imageLoader: ImageLoader
    private let pathDetector = PathDetector()
    private var actionsPanel: ActionMenuPanel?
    private lazy var widgetToast = InspectToastWindow()

    // MARK: Views

    private let contentContainer = DropContainerView()
    private let titlebar = HomeTitlebar()
    private let windowTitleLabel = HomeTextView(font: PanelStyle.inspectFont(ofSize: 13),
                                                color: PanelStyle.textSecondary, alignment: .center)
    private let openSurface = HomeFlippedView()
    private let divider = HomeFlippedView()
    private let recentColumn = HomeFlippedView()
    private let statusbar = HomeFlippedView()
    private let statusLine = HomeFlippedView()
    private let leftStatusLabel = HomeTextView(font: PanelStyle.inspectFont(ofSize: 12),
                                               color: PanelStyle.textTertiary)
    private let centerHintLabel = HomeTextView(font: PanelStyle.monoFont(ofSize: 11),
                                               color: PanelStyle.textTertiary, alignment: .right)

    private lazy var closeTrafficButton = TrafficLightButton(
        color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1),
        target: self, action: #selector(closeTapped))
    private lazy var minimizeTrafficButton = TrafficLightButton(
        color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1),
        target: self, action: #selector(minimizeTapped))
    private lazy var zoomTrafficButton = TrafficLightButton(
        color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1),
        target: self, action: #selector(zoomTapped))
    /// Figma "titlebar actions": 28pt icon buttons at the titlebar's right edge.
    private lazy var tasksButton = makeTitlebarIcon(symbol: "list.bullet", tooltip: "Tasks".localized,
                                                    action: #selector(tasksTapped))
    private lazy var preferencesButton = makeTitlebarIcon(symbol: "slider.horizontal.3",
                                                          tooltip: "Preferences".localized,
                                                          action: #selector(preferencesTapped))
    /// The Pro entry: a pill in the titlebar, left of the icon actions.
    private lazy var proButton: ProPillButton = {
        let button = ProPillButton()
        button.target = self
        button.action = #selector(proTapped)
        return button
    }()

    // Open surface (no folder loaded)
    private let eyebrowLabel = HomeTextView(font: PanelStyle.monoFont(ofSize: 11),
                                            color: PanelStyle.textTertiary, kern: 1.2)
    private let welcomeLabel = HomeTextView(font: PanelStyle.titleFont(ofSize: 34),
                                            color: PanelStyle.textPrimary)
    private let welcomeSubLabel = HomeTextView(font: PanelStyle.inspectFont(ofSize: 13),
                                               color: PanelStyle.textSecondary)
    private let dropZone = DropZoneView()
    private let dropIconView = NSImageView()
    private let dropTitleLabel = HomeTextView(font: PanelStyle.inspectFont(ofSize: 15, weight: .medium),
                                              color: PanelStyle.textPrimary, alignment: .center)
    private let dropHintLabel = HomeTextView(font: PanelStyle.monoFont(ofSize: 11),
                                             color: PanelStyle.textTertiary, alignment: .center)
    private lazy var openFilesButton = HomeWindow.primaryButton(
        title: "Open Files…".localized, target: self, action: #selector(openFilesTapped))
    private lazy var openFolderButton = HomeWindow.secondaryButton(
        title: "Open Folder…".localized, target: self, action: #selector(openFolderTapped))

    // Folder-loaded state
    private let folderGroupLabel = HomeTextView(font: PanelStyle.monoFont(ofSize: 11),
                                                color: PanelStyle.textTertiary, kern: 1.2,
                                                truncation: .middle)
    private let folderCountLabel = HomeTextView(font: PanelStyle.titleFont(ofSize: 34),
                                                color: PanelStyle.textPrimary)
    private lazy var chooseAnotherButton = HomeWindow.secondaryButton(
        title: "Choose another".localized, target: self, action: #selector(openFolderTapped))
    private let folderScroll = NSScrollView()
    private let folderDocView = HomeFlippedView()
    private let folderIndicator = GlanceScrollIndicator(axis: .vertical)
    private lazy var folderPreviousButton = makeFolderArrow(
        symbol: "chevron.up", tooltip: "Previous images".localized,
        action: #selector(previousFolderImagesTapped))
    private lazy var folderNextButton = makeFolderArrow(
        symbol: "chevron.down", tooltip: "Next images".localized,
        action: #selector(nextFolderImagesTapped))
    private let inspectAllButton: PanelButton
    private var currentFolder: URL?
    private var folderImageURLs: [URL] = []
    private var folderThumbViews: [Int: HomeFolderThumbnailView] = [:]
    private var folderGeneration = UUID()
    private var folderColumns = 0
    private var folderTileSize = NSSize.zero

    // Recent
    private let recentHeadingLabel = HomeTextView(font: PanelStyle.inspectFont(ofSize: 13, weight: .medium),
                                                  color: PanelStyle.textPrimary)
    private let recentScroll = NSScrollView()
    private let recentDocView = HomeFlippedView()
    private var recentRows: [RecentRowView] = []
    // Recent empty state (Figma `47 · Empty states` · "Nothing here yet")
    private let emptyIconView = NSImageView()
    private let emptyTitleLabel = HomeTextView(font: PanelStyle.titleFont(ofSize: 20),
                                               color: PanelStyle.textPrimary, alignment: .center)
    private let emptySubLabel = HomeTextView(font: PanelStyle.inspectFont(ofSize: 12),
                                             color: PanelStyle.textTertiary, alignment: .center)
    private lazy var emptyOpenButton = HomeWindow.secondaryButton(
        title: "Open Files…".localized, target: self, action: #selector(openFilesTapped))

    // MARK: Init

    init(imageLoader: ImageLoader) {
        self.imageLoader = imageLoader
        self.inspectAllButton = HomeWindow.primaryButton(title: "", target: nil, action: nil)
        super.init(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        delegate = self
        title = "Glance".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = PanelStyle.windowAppearance
        backgroundColor = HomeStyle.window
        isMovableByWindowBackground = false
        minSize = NSSize(width: 900, height: 580)
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
        NotificationCenter.default.addObserver(self, selector: #selector(proStateChanged),
                                               name: BillingManager.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(proStateChanged),
                                               name: .authDidChange, object: nil)
        updateProEntry()

        setFrame(ScreenManager.shared.contentFrame(for: Self.openingSize), display: false)
        layoutContent()
        // The content view's bounds settle after the frame is applied; lay out
        // once more on the next turn so the recent list builds at its real size.
        DispatchQueue.main.async { [weak self] in self?.layoutContent() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Build

    private func buildUI() {
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = PanelStyle.resolvedCG(HomeStyle.window)
        contentContainer.onFilesDropped = { [weak self] urls in self?.handleDroppedURLs(urls) }
        contentView = contentContainer

        // Titlebar: one surface with the body; no separator (Figma 02).
        contentContainer.addSubview(titlebar)
        titlebar.addSubview(windowTitleLabel)
        titlebar.addSubview(closeTrafficButton)
        titlebar.addSubview(minimizeTrafficButton)
        titlebar.addSubview(zoomTrafficButton)
        titlebar.addSubview(proButton)
        titlebar.addSubview(tasksButton)
        titlebar.addSubview(preferencesButton)

        contentContainer.addSubview(openSurface)
        buildOpenSurface()

        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.resolvedCG(HomeStyle.line)
        contentContainer.addSubview(divider)

        contentContainer.addSubview(recentColumn)
        buildRecentColumn()

        // Statusbar: a 1px top rule, status left, shortcut hints right.
        contentContainer.addSubview(statusbar)
        statusLine.wantsLayer = true
        statusLine.layer?.backgroundColor = PanelStyle.resolvedCG(HomeStyle.line)
        statusbar.addSubview(statusLine)
        statusbar.addSubview(leftStatusLabel)
        statusbar.addSubview(centerHintLabel)

        applyStrings()
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

    private func buildOpenSurface() {
        openSurface.addSubview(eyebrowLabel)
        openSurface.addSubview(welcomeLabel)
        openSurface.addSubview(welcomeSubLabel)

        dropZone.onFilesDropped = { [weak self] urls in self?.handleDroppedURLs(urls) }
        openSurface.addSubview(dropZone)

        dropIconView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        dropIconView.contentTintColor = PanelStyle.textTertiary
        dropIconView.imageScaling = .scaleNone
        dropZone.addSubview(dropIconView)
        dropZone.addSubview(dropTitleLabel)
        dropZone.addSubview(dropHintLabel)
        dropZone.addSubview(openFilesButton)
        dropZone.addSubview(openFolderButton)

        // Folder-loaded state (Figma 46).
        openSurface.addSubview(folderGroupLabel)
        openSurface.addSubview(folderCountLabel)
        openSurface.addSubview(chooseAnotherButton)
        inspectAllButton.target = self
        inspectAllButton.action = #selector(inspectAllTapped)
        openSurface.addSubview(inspectAllButton)

        folderScroll.drawsBackground = false
        folderScroll.borderType = .noBorder
        folderScroll.hasVerticalScroller = false
        folderScroll.hasHorizontalScroller = false
        folderScroll.verticalScrollElasticity = .none
        folderScroll.horizontalScrollElasticity = .none
        folderScroll.documentView = folderDocView
        folderScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(folderClipBoundsChanged),
                                               name: NSView.boundsDidChangeNotification,
                                               object: folderScroll.contentView)
        openSurface.addSubview(folderScroll)
        folderIndicator.onSeek = { [weak self] fraction in self?.seekFolder(to: fraction) }
        folderIndicator.setAccessibilityLabel("Scroll folder images".localized)
        openSurface.addSubview(folderIndicator)
        openSurface.addSubview(folderPreviousButton)
        openSurface.addSubview(folderNextButton)

        setFolderStateHidden(true)
    }

    private func buildRecentColumn() {
        recentColumn.addSubview(recentHeadingLabel)

        recentScroll.drawsBackground = false
        recentScroll.borderType = .noBorder
        recentScroll.hasVerticalScroller = true
        recentScroll.hasHorizontalScroller = false
        recentScroll.verticalScrollElasticity = .allowed
        PanelStyle.styleScrollers(in: recentScroll)
        recentScroll.documentView = recentDocView
        recentColumn.addSubview(recentScroll)

        emptyIconView.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        emptyIconView.contentTintColor = PanelStyle.textTertiary
        emptyIconView.imageScaling = .scaleNone
        recentColumn.addSubview(emptyIconView)
        recentColumn.addSubview(emptyTitleLabel)
        recentColumn.addSubview(emptySubLabel)
        recentColumn.addSubview(emptyOpenButton)
        setRecentEmptyHidden(true)
    }

    private func applyStrings() {
        windowTitleLabel.string = "Glance".localized
        eyebrowLabel.string = "GLANCE  ·  見る"
        welcomeLabel.string = "Open something to inspect".localized
        welcomeSubLabel.string = "Drop images or videos here, or choose files and folders.".localized
        dropTitleLabel.string = "Drag images, videos or a folder here".localized
        dropHintLabel.string = "PNG · JPEG · HEIC · WebP · MP4 · MOV · WebM  and more".localized
        recentHeadingLabel.string = "Recent".localized
        emptyTitleLabel.string = "Nothing here yet".localized
        emptySubLabel.string = "Inspected files show up here.".localized
        centerHintLabel.string = "Drop files anywhere  •  ⌘O to open  •  ⌘⇧O for a folder".localized
        Self.setTitle("Open Files…".localized, on: openFilesButton)
        Self.setTitle("Open Folder…".localized, on: openFolderButton)
        Self.setTitle("Open Files…".localized, on: emptyOpenButton)
        Self.setTitle("Choose another".localized, on: chooseAnotherButton)
        Self.setIconTooltip("Tasks".localized, on: tasksButton)
        Self.setIconTooltip("Preferences".localized, on: preferencesButton)
        folderPreviousButton.toolTip = "Previous images".localized
        folderNextButton.toolTip = "Next images".localized
        folderIndicator.setAccessibilityLabel("Scroll folder images".localized)
        applyFolderStrings()
    }

    private func applyFolderStrings() {
        let count = folderImageURLs.count
        if let folder = currentFolder {
            folderGroupLabel.string = "FOLDER".localized + "  ·  " + folder.abbreviatedDisplayPath
        }
        folderCountLabel.string = String(format: "%d images ready".localized, count)
        Self.setTitle(String(format: "Inspect all %d images".localized, count), on: inspectAllButton)
        if let folder = currentFolder {
            leftStatusLabel.string = folderImageURLs.isEmpty
                ? "No images in that folder".localized
                : String(format: "%d images found".localized, count) + "  ·  " + folder.abbreviatedDisplayPath
        } else {
            leftStatusLabel.string = "No file open  •  Open images to begin".localized
        }
    }

    // MARK: Layout

    private func layoutContent() {
        let W = contentContainer.bounds.width
        let H = contentContainer.bounds.height
        guard W > 0, H > 0 else { return }
        applyBackingScale()

        layoutTitlebar(width: W)

        // Statusbar (flipped container: y grows downward).
        statusbar.frame = NSRect(x: 0, y: H - Metric.statusH, width: W, height: Metric.statusH)
        statusLine.frame = NSRect(x: 0, y: 0, width: W, height: 1)
        let hintW = min(centerHintLabel.textWidth, max(0, W * 0.6))
        centerHintLabel.frame = NSRect(x: W - 20 - hintW, y: 10, width: hintW, height: 14)
        leftStatusLabel.frame = NSRect(x: 20, y: 9, width: max(0, W - 20 - hintW - 16 - 20), height: 15)

        // Body
        let bodyH = max(0, H - Metric.titlebarH - Metric.statusH)
        let leftW = max(0, W - Metric.recentWidth)
        openSurface.frame = NSRect(x: 0, y: Metric.titlebarH, width: leftW, height: bodyH)
        divider.frame = NSRect(x: leftW, y: Metric.titlebarH, width: 1, height: bodyH)
        recentColumn.frame = NSRect(x: leftW + 1, y: Metric.titlebarH,
                                    width: Metric.recentWidth - 1, height: bodyH)

        layoutOpenSurface()
        layoutRecentColumn()
    }

    private func layoutTitlebar(width W: CGFloat) {
        titlebar.frame = NSRect(x: 0, y: 0, width: W, height: Metric.titlebarH)
        let dot: CGFloat = 12
        closeTrafficButton.frame = NSRect(x: 20, y: 16, width: dot, height: dot)
        minimizeTrafficButton.frame = NSRect(x: 40, y: 16, width: dot, height: dot)
        zoomTrafficButton.frame = NSRect(x: 60, y: 16, width: dot, height: dot)
        windowTitleLabel.frame = NSRect(x: 120, y: 14, width: max(0, W - 240), height: 16)

        // Icon actions: 28pt, 4pt apart, 20pt from the right edge, y 8.
        preferencesButton.frame = NSRect(x: W - 20 - 28, y: 8, width: 28, height: 28)
        tasksButton.frame = NSRect(x: W - 20 - 28 - 32, y: 8, width: 28, height: 28)
        // The Pro pill sits 8pt left of the icon actions (its frame carries a focus margin).
        let proWidth = proButton.preferredWidth, proHeight = proButton.preferredHeight
        proButton.frame = NSRect(x: tasksButton.frame.minX - 8 + ProPillButton.margin - proWidth,
                                 y: (Metric.titlebarH - proHeight) / 2,
                                 width: proWidth, height: proHeight)
    }

    /// Main column: 856pt wide (Figma), centered in the left area, at least
    /// 40pt from either edge.
    private var mainColumn: (x: CGFloat, width: CGFloat) {
        let w = openSurface.bounds.width
        let contentW = max(0, min(Metric.mainMaxW, w - Metric.mainMinPad * 2))
        return (((w - contentW) / 2).rounded(), contentW)
    }

    private func layoutOpenSurface() {
        if folderImageURLs.isEmpty { layoutOpenState() } else { layoutFolderState() }
    }

    /// Figma 02 · Home: eyebrow, title, one line of copy, then the drop zone,
    /// centered vertically in the body.
    private func layoutOpenState() {
        let h = openSurface.bounds.height
        let (x, contentW) = mainColumn
        let dropH = min(Metric.dropMaxH, max(Metric.dropMinH, h - 64 - 150))
        let top = max(32, ((h - 150 - dropH) / 2).rounded())

        eyebrowLabel.frame = NSRect(x: x, y: top, width: contentW, height: 14)
        welcomeLabel.frame = NSRect(x: x, y: top + 34, width: contentW, height: 44)
        welcomeSubLabel.frame = NSRect(x: x, y: top + 88, width: contentW, height: 22)
        dropZone.frame = NSRect(x: x, y: top + 150, width: contentW, height: dropH)

        // Drop zone content (Figma: icon 78, title 122, formats 148, actions 190):
        // a 144pt group centered vertically; the icon drops out when short.
        let showIcon = dropH >= 176
        let groupH: CGFloat = showIcon ? 144 : 100
        let groupTop = ((dropH - groupH) / 2).rounded()
        let textTop = showIcon ? groupTop + 44 : groupTop
        dropIconView.isHidden = !showIcon
        dropIconView.frame = NSRect(x: ((contentW - 24) / 2).rounded(), y: groupTop, width: 24, height: 24)
        dropTitleLabel.frame = NSRect(x: 16, y: textTop, width: max(0, contentW - 32), height: 18)
        dropHintLabel.frame = NSRect(x: 16, y: textTop + 26, width: max(0, contentW - 32), height: 14)
        let filesW = Self.buttonWidth(openFilesButton, minimum: 109)
        let folderW = Self.buttonWidth(openFolderButton, minimum: 120)
        let actionsX = ((contentW - filesW - 8 - folderW) / 2).rounded()
        openFilesButton.frame = NSRect(x: actionsX, y: textTop + 68, width: filesW, height: 32)
        openFolderButton.frame = NSRect(x: actionsX + filesW + 8, y: textTop + 68, width: folderW, height: 32)
    }

    /// Figma 46 · Home / Folder loaded: eyebrow with the path, "N images ready"
    /// with its actions on the right, and the folder grid below.
    private func layoutFolderState() {
        let h = openSurface.bounds.height
        let (x, contentW) = mainColumn
        let top = min(76, max(32, (h * 0.09).rounded()))

        folderGroupLabel.frame = NSRect(x: x, y: top, width: contentW, height: 14)
        let rowY = top + 32
        let inspectW = Self.buttonWidth(inspectAllButton, minimum: 164)
        let chooseW = Self.buttonWidth(chooseAnotherButton, minimum: 134)
        inspectAllButton.frame = NSRect(x: x + contentW - inspectW, y: rowY + 12, width: inspectW, height: 32)
        chooseAnotherButton.frame = NSRect(x: inspectAllButton.frame.minX - 16 - chooseW, y: rowY + 12,
                                           width: chooseW, height: 32)
        folderCountLabel.frame = NSRect(x: x, y: rowY,
                                        width: max(0, chooseAnotherButton.frame.minX - 16 - x), height: 44)

        let gridTop = rowY + 76
        let gridH = max(99, h - 32 - gridTop)
        folderScroll.frame = NSRect(x: x, y: gridTop, width: contentW, height: gridH)
        // The scrollbar lane sits in the margin right of the grid.
        folderIndicator.frame = NSRect(x: x + contentW + 8, y: gridTop, width: 12, height: gridH)
        folderPreviousButton.frame = NSRect(x: x + contentW - 40, y: gridTop + 8, width: 32, height: 32)
        folderNextButton.frame = NSRect(x: x + contentW - 40, y: gridTop + gridH - 40, width: 32, height: 32)
        layoutFolderGrid()
    }

    private func layoutRecentColumn() {
        // recentColumn is flipped and starts 1pt right of the divider.
        let h = recentColumn.bounds.height
        let x = Metric.recentInset - 1
        let headerTop: CGFloat = 28  // Figma y 72 − titlebar 44
        recentHeadingLabel.frame = NSRect(x: x + 12, y: headerTop + 6, width: Metric.recentListW - 24, height: 16)

        let listTop = headerTop + 42
        let listH = max(0, h - listTop - 16)
        recentScroll.frame = NSRect(x: x, y: listTop, width: Metric.recentListW, height: listH)
        relayoutRecentRows()

        // Empty state group (Figma 47: icon, 6, title 28, 10, line 19, 28, button 32).
        let groupH: CGFloat = 167
        let groupTop = listTop + max(0, ((listH - groupH) / 2 - 24).rounded())
        let colW = Metric.recentListW
        emptyIconView.frame = NSRect(x: x + ((colW - 24) / 2).rounded(), y: groupTop, width: 24, height: 24)
        emptyTitleLabel.frame = NSRect(x: x, y: groupTop + 50, width: colW, height: 28)
        emptySubLabel.frame = NSRect(x: x + 28, y: groupTop + 88, width: colW - 56, height: 19)
        let buttonW = Self.buttonWidth(emptyOpenButton, minimum: 111)
        emptyOpenButton.frame = NSRect(x: x + ((colW - buttonW) / 2).rounded(), y: groupTop + 135,
                                       width: buttonW, height: 32)
    }

    // MARK: Recent rows

    private var recentNeedsRefresh = false

    func refresh() {
        recentNeedsRefresh = false
        rebuildRecent()
    }

    private func rebuildRecent() {
        for row in recentRows { row.removeFromSuperview() }
        recentRows.removeAll()

        var seen = Set<String>()
        let entries: [(info: MediaInfo, date: Date)] = HistoryManager.shared.records
            .flatMap { record in record.items.map { (item: $0, date: record.timestamp) } }
            .filter { seen.insert($0.item.value).inserted }
            .compactMap { entry -> (info: MediaInfo, date: Date)? in
                guard let path = entry.item.detectedPath, let info = MediaInfo.from(path) else { return nil }
                return (info: info, date: entry.date)
            }

        setRecentEmptyHidden(!entries.isEmpty)
        for entry in entries {
            let row = RecentRowView(info: entry.info, timestamp: entry.date)
            let captured = entry.info
            row.onTap = { [weak self] in self?.onOpenRecent?(captured) }
            recentDocView.addSubview(row)
            recentRows.append(row)
            loadThumbnail(for: entry.info, row: row)
        }
        relayoutRecentRows()
    }

    private func setRecentEmptyHidden(_ hidden: Bool) {
        emptyIconView.isHidden = hidden
        emptyTitleLabel.isHidden = hidden
        emptySubLabel.isHidden = hidden
        emptyOpenButton.isHidden = hidden
        recentScroll.isHidden = !hidden
    }

    private func relayoutRecentRows() {
        var contentW = recentScroll.contentSize.width
        if contentW <= 0 { contentW = recentScroll.frame.width }
        guard contentW > 0 else { return }

        for (idx, row) in recentRows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(idx) * Metric.rowPitch, width: contentW, height: Metric.rowH)
        }
        let listH = recentRows.isEmpty ? 0
            : CGFloat(recentRows.count - 1) * Metric.rowPitch + Metric.rowH
        recentDocView.frame = NSRect(x: 0, y: 0, width: contentW,
                                     height: max(listH, recentScroll.contentSize.height))
    }

    private func loadThumbnail(for info: MediaInfo, row: RecentRowView) {
        switch info.kind {
        case .image:
            imageLoader.loadImage(from: info.url) { [weak row] image in
                DispatchQueue.main.async {
                    if let image = image { row?.setImage(image) } else { row?.setFailed() }
                }
            }
        case .video:
            row.setPlaceholder(for: info)
            imageLoader.loadVideoThumbnail(from: info.url) { [weak row] image in
                if let image { row?.setImage(image) }
            }
        default:
            row.setPlaceholder(for: info)
        }
    }

    // MARK: Folder grid

    private func setFolderStateHidden(_ hidden: Bool) {
        folderGroupLabel.isHidden = hidden
        folderCountLabel.isHidden = hidden
        chooseAnotherButton.isHidden = hidden
        inspectAllButton.isHidden = hidden
        folderScroll.isHidden = hidden
        folderIndicator.isHidden = hidden
        folderPreviousButton.isHidden = hidden
        folderNextButton.isHidden = hidden
        // The open surface and the folder state share the main column.
        eyebrowLabel.isHidden = !hidden
        welcomeLabel.isHidden = !hidden
        welcomeSubLabel.isHidden = !hidden
        dropZone.isHidden = !hidden
    }

    func showFolder(_ folder: URL, imageURLs: [URL]) {
        folderGeneration = UUID()
        currentFolder = folder
        folderImageURLs = imageURLs
        applyFolderStrings()
        setFolderStateHidden(imageURLs.isEmpty)
        rebuildFolderGrid()
        folderScroll.contentView.scroll(to: .zero)
        folderScroll.reflectScrolledClipView(folderScroll.contentView)
        layoutOpenSurface()
    }

    private func rebuildFolderGrid() {
        for v in folderThumbViews.values { v.removeFromSuperview() }
        folderThumbViews.removeAll()
        folderColumns = 0
    }

    private func layoutFolderGrid() {
        let viewportW = folderScroll.contentSize.width
        let viewportH = folderScroll.contentSize.height
        guard viewportW > 0 else { return }
        let gap = Metric.gridGap
        let columns = max(1, Int((viewportW + gap) / (Metric.gridTile + gap)))
        let tileW = ((viewportW - CGFloat(columns - 1) * gap) / CGFloat(columns)).rounded(.down)
        let tile = NSSize(width: tileW, height: (tileW * 0.75).rounded())
        if columns != folderColumns || tile != folderTileSize {
            // Geometry changed: thumbnails re-place from the loader's cache.
            for v in folderThumbViews.values { v.removeFromSuperview() }
            folderThumbViews.removeAll()
            folderColumns = columns
            folderTileSize = tile
        }
        let rows = (folderImageURLs.count + columns - 1) / columns
        let gridH = rows == 0 ? 0 : CGFloat(rows) * tile.height + CGFloat(rows - 1) * gap
        folderDocView.frame = NSRect(x: 0, y: 0, width: viewportW, height: max(viewportH, gridH))
        let maxOffset = max(0, gridH - viewportH)
        folderScroll.contentView.scroll(to: NSPoint(x: 0, y: min(folderScroll.contentView.bounds.minY, maxOffset)))
        folderScroll.reflectScrolledClipView(folderScroll.contentView)
        updateFolderNavigation()
        updateVisibleFolderThumbnails()
    }

    private func updateVisibleFolderThumbnails() {
        let height = folderScroll.contentSize.height
        let columns = folderColumns
        guard height > 0, columns > 0, !folderImageURLs.isEmpty else { return }
        let tile = folderTileSize
        let pitch = tile.height + Metric.gridGap
        let rows = (folderImageURLs.count + columns - 1) / columns
        let overflow = max(0, folderDocView.bounds.height - height)
        let offset = min(max(0, folderScroll.contentView.bounds.minY), overflow)
        let firstRow = max(0, Int(offset / pitch) - 2)
        let lastRow = min(rows - 1, Int((offset + height) / pitch) + 2)
        guard firstRow <= lastRow else { return }
        let first = firstRow * columns
        let last = min(folderImageURLs.count - 1, (lastRow + 1) * columns - 1)
        let visible = Set(first...last)
        for index in folderThumbViews.keys.filter({ !visible.contains($0) }) {
            folderThumbViews.removeValue(forKey: index)?.removeFromSuperview()
        }
        let generation = folderGeneration
        for index in first...last where folderThumbViews[index] == nil {
            let url = folderImageURLs[index]
            let thumb = HomeFolderThumbnailView(radius: PanelStyle.Radius.thumb)
            thumb.frame = NSRect(x: CGFloat(index % columns) * (tile.width + Metric.gridGap),
                                 y: CGFloat(index / columns) * pitch,
                                 width: tile.width, height: tile.height)
            thumb.toolTip = url.lastPathComponent
            thumb.setAccessibilityLabel(url.lastPathComponent)
            thumb.onOpen = { [weak self] in self?.onOpenImages?([url]) }
            folderDocView.addSubview(thumb)
            folderThumbViews[index] = thumb
            imageLoader.loadThumbnail(from: url) { [weak self, weak thumb] image in
                guard let self, let thumb, self.folderGeneration == generation,
                      self.folderThumbViews[index] === thumb else { return }
                thumb.image = image
            }
        }
    }

    private func makeFolderArrow(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = PanelStyle.makeIconButton(symbol: symbol, tooltip: tooltip,
                                               target: self, action: action)
        button.contentTintColor = PanelStyle.textSecondary
        button.wantsLayer = true
        button.layer?.backgroundColor = PanelStyle.resolvedCG(HomeStyle.well)
        button.layer?.borderColor = PanelStyle.resolvedCG(HomeStyle.line)
        button.layer?.borderWidth = 1
        button.layer?.cornerRadius = 16
        return button
    }

    private func makeTitlebarIcon(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = PanelStyle.makeIconButton(symbol: symbol, tooltip: tooltip,
                                               target: self, action: action)
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        button.contentTintColor = PanelStyle.textSecondary
        button.setAccessibilityLabel(tooltip)
        return button
    }

    @objc private func folderClipBoundsChanged(_ notification: Notification) {
        updateFolderNavigation()
        updateVisibleFolderThumbnails()
    }

    private func updateFolderNavigation() {
        let overflow = max(0, folderDocView.bounds.height - folderScroll.contentSize.height)
        let offset = min(max(0, folderScroll.contentView.bounds.minY), overflow)
        let folderHidden = folderImageURLs.isEmpty
        folderIndicator.update(contentLength: folderDocView.bounds.height,
                               viewportLength: folderScroll.contentSize.height, offset: offset)
        if folderHidden { folderIndicator.isHidden = true }
        folderPreviousButton.isHidden = folderHidden || overflow < 1 || offset < 1
        folderNextButton.isHidden = folderHidden || overflow < 1 || offset >= overflow - 1
    }

    private func seekFolder(to fraction: CGFloat) {
        let overflow = max(0, folderDocView.bounds.height - folderScroll.contentSize.height)
        scrollFolder(to: min(max(0, fraction), 1) * overflow)
    }

    private func scrollFolder(to offset: CGFloat) {
        let overflow = max(0, folderDocView.bounds.height - folderScroll.contentSize.height)
        folderScroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, offset), overflow)))
        folderScroll.reflectScrolledClipView(folderScroll.contentView)
        updateFolderNavigation()
        updateVisibleFolderThumbnails()
    }

    @objc private func previousFolderImagesTapped() {
        scrollFolder(to: folderScroll.contentView.bounds.minY - folderScroll.contentSize.height * 0.8)
    }

    @objc private func nextFolderImagesTapped() {
        scrollFolder(to: folderScroll.contentView.bounds.minY + folderScroll.contentSize.height * 0.8)
    }

    // MARK: Buttons

    /// Figma Button / primary: text-1 fill, ink label, Inter Medium 13, radius 6.
    private static func primaryButton(title: String, target: AnyObject?, action: Selector?) -> PanelButton {
        let button = PanelStyle.makePrimaryButton(title: title, target: target, action: action)
        button.normalBackground = PanelStyle.contrast
        button.hoverBackground = PanelStyle.accentHover
        button.titleColor = PanelStyle.accentInk
        button.titleFont = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        button.layer?.cornerRadius = PanelStyle.Radius.control
        button.layer?.borderWidth = 0
        return button
    }

    /// Figma Button / secondary: ink-2 fill, 1px line border, text-1 label.
    private static func secondaryButton(title: String, target: AnyObject?, action: Selector?) -> PanelButton {
        let button = PanelStyle.makeQuietButton(title: title, target: target, action: action)
        button.normalBackground = HomeStyle.well
        button.hoverBackground = HomeStyle.hover
        button.titleColor = PanelStyle.textPrimary
        button.titleFont = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        button.layer?.cornerRadius = PanelStyle.Radius.control
        button.layer?.borderWidth = 1
        button.layer?.borderColor = PanelStyle.resolvedCG(HomeStyle.line)
        return button
    }

    /// Replace a PanelButton's title and re-apply its styled attributed title.
    private static func setTitle(_ title: String, on button: PanelButton) {
        button.title = title
        button.setAccessibilityLabel(title)
        let font = button.titleFont
        button.titleFont = font
    }

    private static func setIconTooltip(_ tooltip: String, on button: NSButton) {
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
    }

    /// Figma widths for English, grown for longer localized labels (16pt padding each side).
    private static func buttonWidth(_ button: PanelButton, minimum: CGFloat) -> CGFloat {
        let text = ceil((button.title as NSString).size(withAttributes: [.font: button.titleFont]).width)
        return max(minimum, text + 32)
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
        applyStrings()
        for row in recentRows { row.refreshTexts() }
        updateProEntry()
        layoutContent()
    }

    private func updateProEntry() {
        let manager = BillingManager.shared
        let hidden = manager.shouldManagePro
        proButton.isHidden = hidden
        proButton.price = hidden ? nil : manager.proEntryPriceText
        // The promise is the tooltip: the pill itself stays small.
        proButton.toolTip = hidden ? nil : "One-time purchase · Lifetime updates".localized
        proButton.setAccessibilityLabel(hidden ? "" : manager.proEntryTitle)
        layoutContent()
    }

    @objc private func proStateChanged() {
        DispatchQueue.main.async { [weak self] in self?.updateProEntry() }
    }

    @objc private func proTapped() {
        BillingCoordinator.shared.showProEntry(over: self)
    }

    @objc private func historyChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recentNeedsRefresh = true
            // Opening a folder records its local images, then hides Home.
            // Do not fetch unrelated history thumbnails behind Image Inspect.
            guard self.isVisible else { return }
            self.refresh()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateProEntry()
        if recentNeedsRefresh { refresh() }
    }

    func windowDidResize(_ notification: Notification) {
        layoutContent()
        let size = frame.size
        UserDefaults.standard.set(["width": Double(size.width), "height": Double(size.height)],
                                  forKey: Self.savedSizeKey)
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

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            presentHomeMenu(at: convertPoint(toScreen: event.locationInWindow))
            return
        }
        super.sendEvent(event)
    }

    private func presentHomeMenu(at point: NSPoint) {
        var widgetEntries: [ActionMenuEntry] = WidgetRegistry.shared.available.compactMap { widget in
            let commands = widget.localizedCommands.filter { !$0.isTextOnly }
            guard let first = commands.first else { return nil }
            func entry(_ command: WidgetCommand) -> ActionMenuEntry {
                ActionMenuEntry(title: commands.count == 1 ? widget.displayName : command.name,
                                creditCost: widget.taskCreditCost, action: { [weak self] in
                    self?.showMissingWidgetInput(for: command)
                })
            }
            return commands.count == 1 ? entry(first)
                : ActionMenuEntry(title: widget.displayName, creditCost: widget.taskCreditCost, submenu: commands.map(entry))
        }
        let textEntries = TextWidgetPanel.menuEntries()
        if !widgetEntries.isEmpty && !textEntries.isEmpty { widgetEntries.append(.separator()) }
        widgetEntries.append(contentsOf: textEntries)

        let market = ActionMenuEntry(title: "Widget Market…".localized, showsDisclosure: true, action: { [weak self] in
            guard let self else { return }
            WidgetMarketPanel.shared.toggle(from: self)
        })
        let widgetMenu: ActionMenuEntry
        if widgetEntries.isEmpty {
            widgetMenu = market
        } else {
            widgetEntries.append(.separator())
            widgetEntries.append(market)
            widgetMenu = ActionMenuEntry(title: "Widgets".localized, submenu: widgetEntries)
        }
        actionsPanel?.dismissChain()
        let panel = ActionMenuPanel(entries: [
            widgetMenu, .separator(),
            ActionMenuEntry(title: "Open Files…".localized, action: { [weak self] in self?.openFilesTapped() }),
            ActionMenuEntry(title: "Open Folder…".localized, action: { [weak self] in self?.openFolderTapped() })
        ])
        actionsPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.present(at: point)
    }

    private func showMissingWidgetInput(for command: WidgetCommand) {
        let message: String
        switch (command.inputTypes.contains("image"), command.inputTypes.contains("video")) {
        case (true, false): message = "Open an image to use this Widget.".localized
        case (false, true): message = "Open a video to use this Widget.".localized
        case (true, true): message = "Open an image or video to use this Widget.".localized
        case (false, false): message = "Open a compatible file to use this Widget.".localized
        }
        widgetToast.show(message: message, over: self)
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

        // 2) A copied URL/path in text form takes precedence over any image
        // representation that the browser also put on the pasteboard.
        if let text = pb.string(forType: .string), openPastedLocation(text) {
            return true
        }

        // Browser copies may offer only public.url plus a flattened TIFF.
        // Fetch the original URL before falling back to that still bitmap.
        if let text = ImageInspectWindow.clipboardText(), openPastedLocation(text) {
            return true
        }

        // 3) Preserve original encoded image data, including animation.
        if let url = Self.materializeClipboardImage() {
            onOpenImages?([url])
            return true
        }

        NSSound.beep()
        return false
    }

    private func openPastedLocation(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if let remote = URL(string: text), ["http", "https"].contains(remote.scheme?.lowercased() ?? ""),
           remote.host != nil {
            // Save the image to ~/Downloads/Glance first so it can be found in
            // Finder; open the link directly if it can't be saved.
            PastedImageDownloader.save(remote) { [weak self] local in
                self?.onOpenImages?([local ?? remote])
            }
            return true
        }
        let expanded = UserHome.expandingTilde(text)
        let fileURL = URL(fileURLWithPath: expanded)
        if case .localImage = pathDetector.localKind(for: fileURL.path) {
            onOpenImages?([fileURL])
            return true
        }
        return false
    }

    /// Preserve the encoded clipboard image in a temporary file.
    private static func materializeClipboardImage() -> URL? {
        ClipboardImageImport.materialize(from: .general)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Style

/// Shizuka tokens the Home window uses beyond PanelStyle's named roles.
private enum HomeStyle {
    /// ink/1 — the single window surface (titlebar, body, status bar).
    static let window = PanelStyle.surface
    /// ink/2 — drop zone and secondary-button fill.
    static let well = PanelStyle.themed(PanelStyle.Sumi.ink2, PanelStyle.Washi.ink2)
    /// ink/3 — row hover, thumbnail placeholder, pressed/targeted fills.
    static let hover = PanelStyle.themed(PanelStyle.Sumi.ink3, PanelStyle.Washi.ink3)
    /// line — the one hairline (divider, status rule, button border).
    static let line = PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line)
    /// line/strong — the drop zone's dashed edge.
    static let lineStrong = PanelStyle.themed(PanelStyle.Sumi.lineStrong, PanelStyle.Washi.lineStrong)
}

// MARK: - Supporting views

private class HomeFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A single-line text frame that stays 1:1 with its Figma text node: the line
/// box (ascent + descent) is centered in the frame, independent of
/// NSTextField cell padding or intrinsic size.
private final class HomeTextView: NSView {
    var string = "" { didSet { setAccessibilityLabel(string); needsDisplay = true } }
    var font: NSFont { didSet { needsDisplay = true } }
    var textColor: NSColor { didSet { needsDisplay = true } }
    var alignment: NSTextAlignment { didSet { needsDisplay = true } }
    private let kern: CGFloat
    private let truncation: CTLineTruncationType

    init(font: NSFont, color: NSColor, alignment: NSTextAlignment = .left,
         kern: CGFloat = 0, truncation: CTLineTruncationType = .end) {
        self.font = font
        self.textColor = color
        self.alignment = alignment
        self.kern = kern
        self.truncation = truncation
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var attributes: [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        if kern != 0 { attrs[.kern] = kern }
        return attrs
    }

    /// Typographic width of the full string.
    var textWidth: CGFloat {
        guard !string.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        return ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !string.isEmpty, bounds.width > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let attrs = attributes
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
        var shown = line
        if CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) > bounds.width {
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))
            shown = CTLineCreateTruncatedLine(line, Double(bounds.width), truncation, token) ?? line
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(shown, &ascent, &descent, &leading))
        let x: CGFloat
        switch alignment {
        case .right: x = bounds.width - width
        case .center: x = ((bounds.width - width) / 2).rounded()
        default: x = 0
        }

        context.saveGState()
        context.clip(to: bounds)
        // CoreText draws bottom-up; undo the flip for the text pass.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: ((bounds.height - ascent - descent) / 2 + descent).rounded())
        CTLineDraw(shown, context)
        context.restoreGState()
    }
}

/// An aspect-fill image well with rounded corners, plus an SF Symbol mode for
/// kinds without a bitmap preview.
private class HomeThumbView: NSView {
    private let symbolView = NSImageView()

    var image: NSImage? {
        didSet {
            symbolView.isHidden = true
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            layer?.contents = image?.layerContents(forContentsScale: scale)
            layer?.contentsScale = scale
        }
    }

    init(radius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        layer?.backgroundColor = PanelStyle.resolvedCG(HomeStyle.hover)
        layer?.contentsGravity = .resizeAspectFill
        symbolView.imageScaling = .scaleNone
        symbolView.isHidden = true
        addSubview(symbolView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    func setSymbol(_ name: String, tint: NSColor) {
        layer?.contents = nil
        symbolView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        symbolView.contentTintColor = tint
        symbolView.isHidden = false
    }

    override func layout() {
        super.layout()
        symbolView.frame = bounds
    }
}

private final class HomeFolderThumbnailView: HomeThumbView {
    var onOpen: (() -> Void)?

    override init(radius: CGFloat) {
        super.init(radius: radius)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onOpen?() }
    override func accessibilityPerformPress() -> Bool { onOpen?(); return true }
}

private final class HomeTitlebar: HomeFlippedView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
}

/// Figma `FileRow`: 40pt thumbnail, filename, "FORMAT · size" in mono, and a
/// relative time on the right. Hover fills the row with ink/3.
private final class RecentRowView: NSView {
    var onTap: (() -> Void)?
    private let info: MediaInfo
    private let timestamp: Date
    private var fileSize: Int64?
    private let thumb = HomeThumbView(radius: PanelStyle.Radius.thumb)
    private let nameLabel = HomeTextView(font: PanelStyle.inspectFont(ofSize: 13),
                                         color: PanelStyle.textPrimary, truncation: .middle)
    private let metaLabel = HomeTextView(font: PanelStyle.monoFont(ofSize: 11),
                                         color: PanelStyle.textTertiary)
    private let timeLabel = HomeTextView(font: PanelStyle.inspectFont(ofSize: 12),
                                         color: PanelStyle.textTertiary, alignment: .right)
    private var hovering = false { didSet { updateBackground() } }
    private var tracking: NSTrackingArea?

    init(info: MediaInfo, timestamp: Date) {
        self.info = info
        self.timestamp = timestamp
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        addSubview(thumb)
        addSubview(nameLabel)
        addSubview(metaLabel)
        addSubview(timeLabel)
        nameLabel.string = info.filename
        thumb.toolTip = "Loading…".localized
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(info.filename)
        refreshTexts()
        loadFileSize()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    func setImage(_ image: NSImage) {
        thumb.image = image
        thumb.toolTip = nil
    }

    func setFailed() {
        thumb.setSymbol("exclamationmark.triangle", tint: PanelStyle.danger)
        thumb.toolTip = "Failed to load".localized
        setAccessibilityHelp("Failed to load".localized)
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
        thumb.setSymbol(symbol, tint: PanelStyle.textTertiary)
        thumb.toolTip = nil
    }

    /// Format, size and time; re-run after a language change.
    func refreshTexts() {
        var parts = [formatText]
        if let fileSize { parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)) }
        metaLabel.string = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        timeLabel.string = Self.timeText(for: timestamp)
        needsLayout = true
    }

    private var formatText: String {
        switch info.formatName {
        case "JPG", "JPEG": return "JPEG"
        case "WEBP": return "WebP"
        case "MD", "MARKDOWN": return "Markdown"
        case "":
            if info.kind == .folder { return "Folder".localized }
            return info.kind == .webPage ? (info.url.host ?? "") : ""
        case let other: return other
        }
    }

    /// Stat local files off the main thread; the size fills in when ready.
    private func loadFileSize() {
        guard info.isLocal, info.kind != .folder else { return }
        let url = info.url
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return }
            DispatchQueue.main.async {
                self?.fileSize = Int64(bytes)
                self?.refreshTexts()
            }
        }
    }

    /// "2m", "1h" today; "Yesterday"; weekday this week; otherwise the date.
    private static func timeText(for date: Date) -> String {
        let locale = Locale(identifier: Preferences.shared.appLanguage.rawValue)
        var calendar = Calendar.current
        calendar.locale = locale
        let now = Date()
        if calendar.isDateInToday(date) {
            let formatter = DateComponentsFormatter()
            formatter.calendar = calendar
            formatter.unitsStyle = .abbreviated
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = now.timeIntervalSince(date) < 3600 ? [.minute] : [.hour]
            return formatter.string(from: max(60, now.timeIntervalSince(date))) ?? ""
        }
        if calendar.isDateInYesterday(date) { return "Yesterday".localized }
        let day = DateFormatter()
        day.locale = locale
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)),
           date >= weekAgo {
            day.setLocalizedDateFormatFromTemplate("EEE")
        } else {
            day.setLocalizedDateFormatFromTemplate("MMMd")
        }
        return day.string(from: date)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        thumb.frame = NSRect(x: 12, y: 8, width: 40, height: 40)
        let timeW = min(timeLabel.textWidth, 96)
        timeLabel.frame = NSRect(x: w - 12 - timeW, y: 20.5, width: timeW, height: 15)
        let textW = max(0, w - 12 - timeW - 12 - 64)
        nameLabel.frame = NSRect(x: 64, y: 11.5, width: textW, height: 16)
        metaLabel.frame = NSRect(x: 64, y: 30.5, width: textW, height: 14)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func updateBackground() {
        layer?.backgroundColor = hovering ? PanelStyle.resolvedCG(HomeStyle.hover) : nil
    }

    override func mouseDown(with event: NSEvent) { onTap?() }
    override func accessibilityPerformPress() -> Bool { onTap?(); return true }
}

/// Figma `drop zone`: ink/2 well with a 1px dashed line/strong edge. While a
/// drag hovers it, the well lifts to ink/3 and the edge to text/2.
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
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = PanelStyle.cornerSmall
        (isTargeted ? HomeStyle.hover : HomeStyle.well).setFill()
        NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius).fill()
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        path.lineWidth = 1
        (isTargeted ? PanelStyle.textSecondary : HomeStyle.lineStrong).setStroke()
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.stroke()
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

/// The window's content view. Flipped so every Figma top-origin frame maps
/// directly; accepts file drops anywhere in the window.
private final class DropContainerView: NSView {
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

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
