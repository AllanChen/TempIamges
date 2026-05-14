import AppKit

/// Resizable window that lists past preview events. Each event renders as a
/// section: a header strip (timestamp + selected-text snippet) followed by a
/// grid of MediaTileView cards — the same tile component the preview panel
/// uses, so history entries look identical to live previews.
final class HistoryWindow: NSWindow {
    private let scrollView = NSScrollView()
    private let docView = FlippedDocView()
    private let emptyLabel = NSTextField(labelWithString: "No preview history yet.")
    private let toolbarBar = NSView()
    private let clearButton = NSButton()

    private let imageLoader = ImageLoader()
    private var sectionViews: [HistorySectionView] = []
    /// Strong refs to viewer windows opened from a tile click.
    private var viewerWindows: [ContentViewerWindow] = []

    // Layout constants shared with HistorySectionView.
    fileprivate static let columns: Int = 4
    fileprivate static let tileSize = NSSize(width: 174, height: 174)
    fileprivate static let tileSpacing: CGFloat = 10
    fileprivate static let sectionSpacing: CGFloat = 22
    fileprivate static let headerHeight: CGFloat = 56
    fileprivate static let contentInset: CGFloat = 18
    fileprivate static let toolbarHeight: CGFloat = 40

    init() {
        let initialSize = NSSize(width: 820, height: 640)
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.title = "Preview History"
        self.isReleasedWhenClosed = false
        self.center()
        self.minSize = NSSize(width: 520, height: 360)

        buildLayout()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyDidChange),
            name: HistoryManager.didChange,
            object: nil
        )
        // Theme switch rebuilds the section list so tiles re-resolve their
        // semantic colours against the new appearance.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyDidChange),
            name: .preferencesDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Pulls the latest records from HistoryManager and rebuilds the section
    /// stack. Safe to call repeatedly.
    func refresh() {
        rebuildSections()
    }

    @objc private func historyDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.rebuildSections()
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let content = contentView else { return }
        let bounds = content.bounds

        // Toolbar
        toolbarBar.frame = NSRect(x: 0, y: bounds.height - Self.toolbarHeight,
                                   width: bounds.width, height: Self.toolbarHeight)
        toolbarBar.autoresizingMask = [.width, .minYMargin]
        toolbarBar.wantsLayer = true
        toolbarBar.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
        sep.autoresizingMask = [.width]
        toolbarBar.addSubview(sep)

        clearButton.bezelStyle = .rounded
        clearButton.title = "Clear History"
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.frame = NSRect(x: bounds.width - 130, y: 8,
                                    width: 116, height: 24)
        clearButton.autoresizingMask = [.minXMargin]
        toolbarBar.addSubview(clearButton)

        content.addSubview(toolbarBar)

        // Scrollable content area
        scrollView.frame = NSRect(x: 0, y: 0,
                                   width: bounds.width,
                                   height: bounds.height - Self.toolbarHeight)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.windowBackgroundColor

        docView.frame = NSRect(x: 0, y: 0, width: bounds.width,
                                height: bounds.height - Self.toolbarHeight)
        scrollView.documentView = docView

        // Empty state
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = NSFont.systemFont(ofSize: 14)
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: 0, y: (bounds.height - 40) / 2,
                                   width: bounds.width, height: 24)
        emptyLabel.autoresizingMask = [.width]
        docView.addSubview(emptyLabel)

        content.addSubview(scrollView)
    }

    private func rebuildSections() {
        // Tear down previous sections so MediaTileView instances release
        // their players / observers.
        for section in sectionViews {
            section.teardown()
            section.removeFromSuperview()
        }
        sectionViews.removeAll()

        // Dedup across the whole history: walk newest → oldest, keep each URL
        // only on the first (most recent) record that contains it. Records
        // left with no items after dedup are skipped entirely.
        var seenURLs = Set<String>()
        let deduped: [HistoryRecord] = HistoryManager.shared.records.compactMap { record in
            let kept = record.items.filter { item in
                seenURLs.insert(item.value).inserted
            }
            guard !kept.isEmpty else { return nil }
            return HistoryRecord(timestamp: record.timestamp,
                                  selectedText: record.selectedText,
                                  items: kept)
        }

        emptyLabel.isHidden = !deduped.isEmpty

        // Group deduped records by day (newest day first).
        let calendar = Calendar.current
        var dayGroups: [(date: Date, items: [HistoryRecord.Item])] = []
        for record in deduped {
            let dayStart = calendar.startOfDay(for: record.timestamp)
            if let idx = dayGroups.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
                dayGroups[idx].items.append(contentsOf: record.items)
            } else {
                dayGroups.append((date: dayStart, items: record.items))
            }
        }
        // Deduplicate items within each day as well.
        dayGroups = dayGroups.map { group in
            var seen = Set<String>()
            let unique = group.items.filter { seen.insert($0.value).inserted }
            return (date: group.date, items: unique)
        }.filter { !$0.items.isEmpty }

        let contentWidth = docView.bounds.width
        let usableWidth = contentWidth - Self.contentInset * 2
        var cursorY: CGFloat = Self.contentInset

        for group in dayGroups {
            let section = HistorySectionView(
                date: group.date,
                items: group.items,
                width: usableWidth,
                imageLoader: imageLoader,
                onTileTap: { [weak self] info in
                    self?.handleTileTap(info: info)
                }
            )
            section.frame.origin = NSPoint(x: Self.contentInset, y: cursorY)
            docView.addSubview(section)
            sectionViews.append(section)
            cursorY += section.frame.height + Self.sectionSpacing
        }

        // Resize the document view so the scroll bar reflects total content.
        let totalHeight = max(cursorY + Self.contentInset,
                              scrollView.contentSize.height)
        docView.frame = NSRect(x: 0, y: 0,
                                width: contentWidth, height: totalHeight)

        // Centre empty label if there's no content.
        if deduped.isEmpty {
            emptyLabel.frame = NSRect(
                x: 0,
                y: scrollView.contentSize.height / 2 - 12,
                width: contentWidth, height: 24
            )
        }
        scrollView.documentView?.scroll(.zero)
    }

    private func handleTileTap(info: MediaInfo) {
        switch info.kind {
        case .image, .video:
            NSWorkspace.shared.open(info.url)
        case .other:
            if info.isLocal {
                NSWorkspace.shared.activateFileViewerSelecting([info.url])
            } else {
                NSWorkspace.shared.open(info.url)
            }
            return
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
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self = self, let window = window else { return }
                self.viewerWindows.removeAll { $0 === window }
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func clearTapped() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "This removes the saved list of past previews. It does not affect any actual files."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { response in
            if response == .alertFirstButtonReturn {
                HistoryManager.shared.clear()
            }
        }
    }

    // The doc view needs to track the scroll-view's content width so tiles
    // re-flow when the user resizes the window.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        DispatchQueue.main.async { [weak self] in
            self?.handleResize()
        }
    }

    private func handleResize() {
        let newWidth = scrollView.contentSize.width
        // Skip if width didn't change — masonry only depends on width.
        if abs(docView.frame.width - newWidth) < 0.5 { return }
        docView.frame.size.width = newWidth
        rebuildSections()
    }
}

// MARK: - Section view

/// One history record rendered as a header strip plus a fixed-column tile
/// grid. Owns its MediaTileView instances and proxies thumbnail loading
/// through the shared ImageLoader.
/// One day's worth of history items rendered as a date header plus a
/// fixed-column tile grid.  Owns its MediaTileView instances and proxies
/// thumbnail loading through the shared ImageLoader.
private final class HistorySectionView: NSView {
    private let date: Date
    private let items: [HistoryRecord.Item]
    private let imageLoader: ImageLoader
    private let onTileTap: (MediaInfo) -> Void
    private var tiles: [MediaTileView] = []

    init(date: Date,
         items: [HistoryRecord.Item],
         width: CGFloat,
         imageLoader: ImageLoader,
         onTileTap: @escaping (MediaInfo) -> Void) {
        self.date = date
        self.items = items
        self.imageLoader = imageLoader
        self.onTileTap = onTileTap
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.0).cgColor

        buildSubviews(width: width)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func teardown() {
        for tile in tiles { tile.teardown() }
        tiles.removeAll()
    }

    // MARK: - Builders

    private func buildSubviews(width: CGFloat) {
        let headerH = HistoryWindow.headerHeight
        let tileW = HistoryWindow.tileSize.width
        let tileH = HistoryWindow.tileSize.height
        let spacing = HistoryWindow.tileSpacing

        // Header: date only
        let header = makeHeader(width: width, height: headerH)
        header.frame.origin = NSPoint(x: 0, y: 0)
        addSubview(header)

        // Tile grid
        let infos: [(info: MediaInfo, item: HistoryRecord.Item)] = items.compactMap { item in
            guard let path = item.detectedPath, let info = MediaInfo.from(path) else { return nil }
            return (info, item)
        }
        let tilesGridY = headerH + 8
        var rowMaxY: CGFloat = tilesGridY

        // Compute columns that actually fit at this width.
        let availableForGrid = max(tileW, width)
        let cols = max(1, Int((availableForGrid + spacing) / (tileW + spacing)))

        for (idx, pair) in infos.enumerated() {
            let row = idx / cols
            let col = idx % cols
            let x = CGFloat(col) * (tileW + spacing)
            let y = tilesGridY + CGFloat(row) * (tileH + spacing)
            let frame = NSRect(x: x, y: y, width: tileW, height: tileH)
            let tile = MediaTileView(info: pair.info, style: .masonry, frame: frame)
            let capturedInfo = pair.info
            tile.onTileTap = { [weak self] in
                self?.onTileTap(capturedInfo)
            }
            // MediaTileView's mouseDown opens image/video URLs directly via
            // NSWorkspace, so no extra gesture recognizer is needed for
            // those kinds — only openable tiles funnel through onTileTap.
            addSubview(tile)
            tiles.append(tile)
            rowMaxY = max(rowMaxY, y + tileH)

            kickOffLoad(for: pair.info, tile: tile)
        }

        let totalH = max(headerH, rowMaxY)
        frame = NSRect(x: 0, y: 0, width: width, height: totalH)
    }

    private func makeHeader(width: CGFloat, height: CGFloat) -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd  EEEE"
        let dateLabel = NSTextField(labelWithString: formatter.string(from: date))
        dateLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        dateLabel.textColor = .labelColor
        dateLabel.frame = NSRect(x: 0, y: (height - 20) / 2, width: width, height: 20)
        dateLabel.lineBreakMode = .byTruncatingTail
        header.addSubview(dateLabel)

        return header
    }

    /// Drive the same async pipeline the live preview uses, so the tile shows
    /// the type-specific icon while loading and the real thumbnail once done.
    private func kickOffLoad(for info: MediaInfo, tile: MediaTileView) {
        switch info.kind {
        case .image:
            imageLoader.loadImage(from: info.url) { [weak tile] image in
                guard let tile = tile, let img = image else {
                    tile?.setFailed(); return
                }
                var enriched = info
                enriched.dimensions = img.size
                tile.setLoaded(.image(img, enriched))
            }
        case .video:
            // Async probe is overkill in history — just hand the URL through
            // so the tile attaches an AVPlayer. AVPlayerView resolves the
            // natural size itself.
            tile.setLoaded(.video(info.url, naturalSize: info.dimensions ?? .zero, info))
        case .markdown, .text, .pdf, .webPage, .other:
            tile.setLoaded(.openable(info))
        }
    }

}
