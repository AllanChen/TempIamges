import AppKit

/// Lists past preview events as a grid of thumbnail cards, styled to match the
/// Figma "Preview History / Clean Editable" frame: a dark titlebar with custom
/// traffic lights, an icon toolbar, a searchable content area, and a statusbar.
///
/// Cards are lightweight self-drawn views (not MediaTileView) so opening the
/// window never blocks the main thread building AVPlayers / masonry tiles — the
/// old cause of the open-time stutter.
final class HistoryWindow: NSWindow, NSWindowDelegate {
    private static let contentSize = NSSize(width: 1040, height: 720)

    private enum Metric {
        static let titlebarH: CGFloat = 52
        static let toolbarH: CGFloat = 56
        static let statusH: CGFloat = 30
        static let pad: CGFloat = 32
        static let card = NSSize(width: 232, height: 176)
        static let spacing: CGFloat = 20
    }

    private let imageLoader = ImageLoader()
    private var viewerWindows: [ContentViewerWindow] = []

    // Chrome
    private let contentContainer = NSView()
    private let titlebar = HistoryTitlebar()
    private let windowTitleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let toolbarBar = NSView()
    private let bodyView = FlippedDocView()
    private let statusbar = NSView()
    private let leftStatusLabel = NSTextField(labelWithString: "")
    private let centerHintLabel = NSTextField(labelWithString: "")

    private lazy var closeTrafficButton = HistoryTrafficLightButton(
        color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1),
        target: self, action: #selector(closeTapped))
    private lazy var minimizeTrafficButton = HistoryTrafficLightButton(
        color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1),
        target: self, action: #selector(minimizeTapped))
    private lazy var zoomTrafficButton = HistoryTrafficLightButton(
        color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1),
        target: self, action: #selector(zoomTapped))

    // Content
    private let sectionTitle = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let gridDocView = FlippedDocView()

    private var allInfos: [MediaInfo] = []
    private var cards: [HistoryCardView] = []
    private var toolbarTrailingButtons: [NSButton] = []

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        delegate = self
        title = "Preview History".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = PanelStyle.inspectBackground
        minSize = NSSize(width: 820, height: 520)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        buildUI()
        setFrame(ScreenManager.shared.contentFrame(for: Self.contentSize), display: false)
        layoutContent()

        NotificationCenter.default.addObserver(self, selector: #selector(historyDidChange),
                                               name: HistoryManager.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
                                               name: .languageDidChange, object: nil)
        DispatchQueue.main.async { [weak self] in self?.layoutContent() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    func refresh() { rebuildCards() }

    // MARK: Build

    private func buildUI() {
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectBackground)
        contentView = contentContainer

        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        contentContainer.addSubview(titlebar)
        configureLabel(windowTitleLabel, size: 15, weight: .semibold, color: PanelStyle.textPrimary, align: .center)
        windowTitleLabel.stringValue = "Preview History".localized
        titlebar.addSubview(windowTitleLabel)
        configureLabel(subtitleLabel, size: 11, color: PanelStyle.textTertiary, align: .center)
        titlebar.addSubview(subtitleLabel)
        titlebar.addSubview(closeTrafficButton)
        titlebar.addSubview(minimizeTrafficButton)
        titlebar.addSubview(zoomTrafficButton)

        toolbarBar.wantsLayer = true
        toolbarBar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        toolbarBar.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        toolbarBar.layer?.borderWidth = 1
        contentContainer.addSubview(toolbarBar)
        addToolbarButton(symbol: "arrow.uturn.backward", tooltip: "Open in Inspect".localized, action: #selector(noop))
        addToolbarButton(symbol: "trash", tooltip: "Clear History".localized, action: #selector(clearTapped), tint: PanelStyle.danger)
        addToolbarButton(symbol: "info.circle", tooltip: "About Glance".localized, action: #selector(noop))

        bodyView.wantsLayer = true
        bodyView.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        contentContainer.addSubview(bodyView)

        configureLabel(sectionTitle, size: 19, weight: .semibold, color: PanelStyle.textPrimary)
        sectionTitle.stringValue = "Today".localized
        bodyView.addSubview(sectionTitle)
        configureLabel(countLabel, size: 11, color: PanelStyle.textTertiary)
        bodyView.addSubview(countLabel)

        searchField.placeholderString = "Search filename".localized
        searchField.font = PanelStyle.inspectFont(ofSize: 12)
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        bodyView.addSubview(searchField)

        configureLabel(emptyLabel, size: 13, color: PanelStyle.textTertiary, align: .center)
        emptyLabel.stringValue = "No preview history yet.".localized
        emptyLabel.isHidden = true
        bodyView.addSubview(emptyLabel)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = gridDocView
        bodyView.addSubview(scrollView)

        statusbar.wantsLayer = true
        statusbar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectStatus)
        statusbar.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        statusbar.layer?.borderWidth = 1
        contentContainer.addSubview(statusbar)
        configureLabel(leftStatusLabel, size: 12, color: PanelStyle.textSecondary)
        statusbar.addSubview(leftStatusLabel)
        configureLabel(centerHintLabel, size: 12, color: PanelStyle.textSecondary, align: .center)
        centerHintLabel.stringValue = "Search by filename, inspect again with one click".localized
        statusbar.addSubview(centerHintLabel)

        rebuildCards()
    }

    private func configureLabel(_ label: NSTextField, size: CGFloat, weight: NSFont.Weight = .regular,
                                color: NSColor, align: NSTextAlignment = .left) {
        label.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = align
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
    }

    private func addToolbarButton(symbol: String, tooltip: String, action: Selector, tint: NSColor? = nil) {
        let btn = PanelStyle.makeIconButton(symbol: symbol, tooltip: tooltip, target: self, action: action)
        if let tint = tint { btn.contentTintColor = tint }
        toolbarBar.addSubview(btn)
        toolbarTrailingButtons.append(btn)
    }

    // MARK: Layout

    private func layoutContent() {
        let W = contentContainer.bounds.width
        let H = contentContainer.bounds.height
        guard W > 0, H > 0 else { return }
        applyBackingScale()

        titlebar.frame = NSRect(x: 0, y: H - Metric.titlebarH, width: W, height: Metric.titlebarH)
        let dot: CGFloat = 12
        let dotY = (Metric.titlebarH - dot) / 2
        closeTrafficButton.frame = NSRect(x: 20, y: dotY, width: dot, height: dot)
        minimizeTrafficButton.frame = NSRect(x: 40, y: dotY, width: dot, height: dot)
        zoomTrafficButton.frame = NSRect(x: 60, y: dotY, width: dot, height: dot)
        windowTitleLabel.frame = NSRect(x: 100, y: Metric.titlebarH / 2, width: W - 200, height: 20)
        subtitleLabel.frame = NSRect(x: 100, y: Metric.titlebarH / 2 - 17, width: W - 200, height: 14)

        toolbarBar.frame = NSRect(x: 0, y: H - Metric.titlebarH - Metric.toolbarH, width: W, height: Metric.toolbarH)
        let btn: CGFloat = 36
        let btnY = (Metric.toolbarH - btn) / 2
        for (i, b) in toolbarTrailingButtons.enumerated() {
            b.frame = NSRect(x: W - 20 - btn - CGFloat(i) * 44, y: btnY, width: btn, height: btn)
        }

        statusbar.frame = NSRect(x: 0, y: 0, width: W, height: Metric.statusH)
        leftStatusLabel.frame = NSRect(x: 20, y: (Metric.statusH - 15) / 2, width: 480, height: 15)
        centerHintLabel.frame = NSRect(x: 0, y: (Metric.statusH - 15) / 2, width: W, height: 15)

        let bodyTop = H - Metric.titlebarH - Metric.toolbarH
        let bodyH = bodyTop - Metric.statusH
        bodyView.frame = NSRect(x: 0, y: Metric.statusH, width: W, height: bodyH)
        layoutBody()
    }

    private func layoutBody() {
        // bodyView is flipped: y grows downward.
        let w = bodyView.bounds.width
        let h = bodyView.bounds.height
        let p = Metric.pad
        sectionTitle.frame = NSRect(x: p, y: 28, width: 300, height: 28)
        countLabel.frame = NSRect(x: p, y: 62, width: 300, height: 15)
        searchField.frame = NSRect(x: w - p - 320, y: 30, width: 320, height: 30)

        let gridTop: CGFloat = 100
        scrollView.frame = NSRect(x: p, y: gridTop, width: max(0, w - p * 2), height: max(0, h - gridTop - 16))
        emptyLabel.frame = NSRect(x: 0, y: gridTop + 60, width: w, height: 20)
        relayoutCards()
    }

    private func applyBackingScale() {
        let scale = backingScaleFactor
        func apply(_ view: NSView) {
            if view.wantsLayer { view.layer?.contentsScale = scale }
            for sub in view.subviews { apply(sub) }
        }
        apply(contentContainer)
    }

    // MARK: Cards

    private func rebuildCards() {
        for card in cards { card.removeFromSuperview() }
        cards.removeAll()

        var seen = Set<String>()
        allInfos = HistoryManager.shared.records
            .flatMap { $0.items }
            .filter { seen.insert($0.value).inserted }
            .compactMap { $0.detectedPath }
            .compactMap { MediaInfo.from($0) }

        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? allInfos
            : allInfos.filter { $0.filename.lowercased().contains(query) }

        for card in cards { card.removeFromSuperview() }
        cards.removeAll()

        emptyLabel.isHidden = !filtered.isEmpty
        for info in filtered {
            let card = HistoryCardView(info: info)
            let captured = info
            card.onTap = { [weak self] in self?.handleTileTap(info: captured) }
            gridDocView.addSubview(card)
            cards.append(card)
            loadThumbnail(for: info, card: card)
        }
        countLabel.stringValue = String(format: "%d items".localized, filtered.count)
        leftStatusLabel.stringValue = "Preview History".localized + "  •  " + String(format: "%d items".localized, allInfos.count)
        subtitleLabel.stringValue = String(format: "%d items today".localized, allInfos.count)
        relayoutCards()
    }

    private func relayoutCards() {
        var contentW = scrollView.contentSize.width
        if contentW <= 0 { contentW = scrollView.frame.width }
        guard contentW > 0 else { return }

        let cardW = Metric.card.width
        let cardH = Metric.card.height
        let spacing = Metric.spacing
        let cols = max(1, Int((contentW + spacing) / (cardW + spacing)))
        var maxY: CGFloat = 0
        for (idx, card) in cards.enumerated() {
            let row = idx / cols
            let col = idx % cols
            let x = (CGFloat(col) * (cardW + spacing)).rounded()
            let y = (CGFloat(row) * (cardH + spacing)).rounded()
            card.frame = NSRect(x: x, y: y, width: cardW, height: cardH)
            maxY = max(maxY, y + cardH)
        }
        let rows = (cards.count + cols - 1) / cols
        let docH = max(CGFloat(rows) * (cardH + spacing), scrollView.contentSize.height)
        gridDocView.frame = NSRect(x: 0, y: 0, width: contentW, height: docH)
    }

    private func loadThumbnail(for info: MediaInfo, card: HistoryCardView) {
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

    // MARK: Actions

    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }
    @objc private func noop() {}
    @objc private func searchChanged() { applyFilter() }

    private func handleTileTap(info: MediaInfo) {
        switch info.kind {
        case .image, .video:
            NSWorkspace.shared.open(info.url)
        case .other, .folder:
            if info.isLocal { NSWorkspace.shared.activateFileViewerSelecting([info.url]) }
            else { NSWorkspace.shared.open(info.url) }
        case .markdown, .text, .pdf, .webPage:
            let window = ContentViewerWindow()
            switch info.kind {
            case .markdown: window.loadMarkdown(info.url)
            case .text:     window.loadText(info.url)
            case .pdf:      window.loadPDF(info.url)
            case .webPage:  window.loadWebPage(info.url)
            default: break
            }
            viewerWindows.append(window)
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                   object: window, queue: .main) { [weak self, weak window] _ in
                guard let self = self, let window = window else { return }
                self.viewerWindows.removeAll { $0 === window }
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func clearTapped() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?".localized
        alert.informativeText = "This removes the saved list of past previews. It does not affect any actual files.".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear".localized)
        alert.addButton(withTitle: "Cancel".localized)
        alert.beginSheetModal(for: self) { response in
            if response == .alertFirstButtonReturn { HistoryManager.shared.clear() }
        }
    }

    @objc private func historyDidChange() {
        DispatchQueue.main.async { [weak self] in self?.rebuildCards() }
    }

    @objc private func languageChanged() {
        windowTitleLabel.stringValue = "Preview History".localized
        sectionTitle.stringValue = "Today".localized
        searchField.placeholderString = "Search filename".localized
        centerHintLabel.stringValue = "Search by filename, inspect again with one click".localized
        applyFilter()
    }

    func windowDidResize(_ notification: Notification) { layoutContent() }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Supporting views

private final class HistoryTitlebar: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
}

private final class HistoryTrafficLightButton: NSButton {
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
    override func layout() { super.layout(); layer?.cornerRadius = bounds.width / 2 }
}

/// Self-drawn history card: thumbnail + filename/type overlay + load states.
private final class HistoryCardView: NSView {
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

    func setImage(_ image: NSImage) { imageView.image = image; stateLabel.isHidden = true }

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
        nameLabel.frame = NSRect(x: 12, y: (overlayH - 16) / 2, width: bounds.width - 64, height: 16)
        typeLabel.frame = NSRect(x: bounds.width - 56, y: (overlayH - 14) / 2, width: 44, height: 14)
        stateLabel.frame = NSRect(x: 0, y: bounds.midY - 8, width: bounds.width, height: 16)
    }

    override func mouseDown(with event: NSEvent) { onTap?() }
}
