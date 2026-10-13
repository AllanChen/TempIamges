import AppKit
import AVFoundation
import ImageIO

/// Preview History, built from the Figma "Preview History Redesign" board:
/// a title bar, one row with search + type filters + Clear History, then the
/// history grouped by day (or a flat result list while searching) as
/// media-first cards.
///
/// Cards are lightweight self-drawn views (not MediaTileView) so opening the
/// window never blocks the main thread building AVPlayers / masonry tiles.
/// Thumbnails are decoded off the main thread at a small size and cached.
final class HistoryWindow: NSWindow, NSWindowDelegate {
    private static let contentSize = NSSize(width: 1280, height: 800)

    // Figma metrics (top-left origin).
    private enum Metric {
        static let titlebarH: CGFloat = 52
        static let rowY: CGFloat = 68
        static let margin: CGFloat = 40
        static let searchSize = NSSize(width: 320, height: 40)
        static let chipsX: CGFloat = 384
        static let chipY: CGFloat = 72
        static let chipH: CGFloat = 32
        static let chipGap: CGFloat = 8
        static let clearSize = NSSize(width: 132, height: 32)
        static let dividerY: CGFloat = 124
        /// Section title sits at y 148 in the window; the scroll view starts at 125.
        static let docTopPad: CGFloat = 23
        static let sectionToCards: CGFloat = 36
        static let afterRow: CGFloat = 28
        static let rowGap: CGFloat = 24
        static let cardGap: CGFloat = 21
        static let minCardW: CGFloat = 240
    }

    private struct Group {
        let title: String
        let entries: [HistoryEntry]
    }

    private let imageLoader = ImageLoader()
    private var viewerWindows: [ContentViewerWindow] = []

    // Chrome
    private let contentContainer = FlippedDocView()
    private let titlebar = HistoryTitlebar()
    private let searchBox = HistorySearchBox(frame: NSRect(origin: .zero, size: Metric.searchSize))
    private let clearButton = HistoryClearButton(frame: NSRect(origin: .zero, size: Metric.clearSize))
    private let divider = NSView()
    private var chips: [(filter: HistoryFilter, view: HistoryChipView)] = []
    private let scrollView = NSScrollView()
    private let gridDocView = FlippedDocView()
    private let emptyView = HistoryEmptyView()
    private let fadeView = HistoryFadeView()

    private lazy var closeTrafficButton = TrafficLightButton(
        color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1),
        target: self, action: #selector(closeTapped))
    private lazy var minimizeTrafficButton = TrafficLightButton(
        color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1),
        target: self, action: #selector(minimizeTapped))
    private lazy var zoomTrafficButton = TrafficLightButton(
        color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1),
        target: self, action: #selector(zoomTapped))

    // Data
    private var entries: [HistoryEntry] = []
    private var selectedFilter = HistoryFilter.all
    private var groups: [Group] = []
    private var headers: [HistorySectionHeader] = []
    private var cards: [HistoryCardView] = []
    private let thumbnailCache = NSCache<NSString, CGImage>()
    private var sizeCache: [String: String] = [:]
    private var durationCache: [String: String] = [:]

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
        backgroundColor = HistoryStyle.background
        minSize = NSSize(width: 1000, height: 560)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        thumbnailCache.countLimit = 400

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

    func refresh() { rebuildEntries() }

    // MARK: Build

    private func buildUI() {
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = PanelStyle.resolvedCG(HistoryStyle.background)
        contentView = contentContainer

        titlebar.title = "Preview History".localized
        contentContainer.addSubview(titlebar)
        titlebar.addSubview(closeTrafficButton)
        titlebar.addSubview(minimizeTrafficButton)
        titlebar.addSubview(zoomTrafficButton)

        searchBox.onChange = { [weak self] in self?.applyFilter() }
        contentContainer.addSubview(searchBox)

        for filter in HistoryFilter.allCases {
            let chip = HistoryChipView(frame: .zero)
            chip.onClick = { [weak self] in
                self?.selectedFilter = filter
                self?.applyFilter()
            }
            contentContainer.addSubview(chip)
            chips.append((filter, chip))
        }

        clearButton.onClick = { [weak self] in self?.clearTapped() }
        contentContainer.addSubview(clearButton)

        divider.wantsLayer = true
        divider.layer?.backgroundColor = HistoryStyle.hairline.cgColor
        contentContainer.addSubview(divider)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = gridDocView
        contentContainer.addSubview(scrollView)

        contentContainer.addSubview(emptyView)
        contentContainer.addSubview(fadeView)
        rebuildEntries()
    }

    private func layoutContent() {
        let W = contentContainer.bounds.width
        let H = contentContainer.bounds.height
        guard W > 0, H > 0 else { return }
        applyBackingScale()

        titlebar.frame = NSRect(x: 0, y: 0, width: W, height: Metric.titlebarH)
        closeTrafficButton.frame = NSRect(x: 20, y: 18, width: 12, height: 12)
        minimizeTrafficButton.frame = NSRect(x: 40, y: 18, width: 12, height: 12)
        zoomTrafficButton.frame = NSRect(x: 60, y: 18, width: 12, height: 12)

        searchBox.frame = NSRect(x: Metric.margin, y: Metric.rowY, width: Metric.searchSize.width, height: Metric.searchSize.height)
        layoutChips()
        clearButton.frame = NSRect(x: W - Metric.margin - Metric.clearSize.width, y: Metric.chipY,
                                   width: Metric.clearSize.width, height: Metric.clearSize.height)
        divider.frame = NSRect(x: 0, y: Metric.dividerY, width: W, height: 1)

        let bodyY = Metric.dividerY + 1
        scrollView.frame = NSRect(x: 0, y: bodyY, width: W, height: H - bodyY)
        emptyView.frame = scrollView.frame
        fadeView.frame = NSRect(x: 0, y: H - 100, width: W, height: 100)
        layoutGrid()
    }

    private func layoutChips() {
        var x = Metric.chipsX
        for (_, chip) in chips {
            let width = chip.fittingWidth
            chip.frame = NSRect(x: x, y: Metric.chipY, width: width, height: Metric.chipH)
            x += width + Metric.chipGap
        }
    }

    private func applyBackingScale() {
        let scale = backingScaleFactor
        func apply(_ view: NSView) {
            if view.wantsLayer { view.layer?.contentsScale = scale }
            for sub in view.subviews { apply(sub) }
        }
        apply(contentContainer)
    }

    // MARK: Data

    private func rebuildEntries() {
        var seen = Set<String>()
        var built: [HistoryEntry] = []
        for record in HistoryManager.shared.records {
            for item in record.items where seen.insert(item.value).inserted {
                guard let info = item.detectedPath.flatMap({ MediaInfo.from($0) }) else { continue }
                let isResult = info.kind == .image && info.isLocal
                    && WidgetTaskManager.shared.completedRecord(for: info.url) != nil
                built.append(HistoryEntry(info: info, timestamp: record.timestamp, isResult: isResult, storedValue: item.value))
            }
        }
        entries = built
        applyFilter()
    }

    private func applyFilter() {
        let query = searchBox.query
        let lowered = query.lowercased()
        let matching = lowered.isEmpty ? entries : entries.filter { $0.info.filename.lowercased().contains(lowered) }

        // Chip counts follow the query; the selected chip filters the list.
        for (filter, chip) in chips {
            let count = matching.filter { filter.matches($0.info) }.count
            chip.title = filter.title
            chip.count = count
            chip.isActive = filter == selectedFilter
            chip.isDimmed = count == 0 && filter != .all || entries.isEmpty
        }
        layoutChips()

        let shown = matching.filter { selectedFilter.matches($0.info) }
        titlebar.subtitle = lowered.isEmpty
            ? String(format: "%d previews".localized, entries.count)
            : String(format: "%d results".localized, shown.count)
        clearButton.isHidden = entries.isEmpty
        searchBox.alphaValue = entries.isEmpty ? 0.5 : 1

        groups = lowered.isEmpty
            ? Self.dayGroups(for: shown)
            : (shown.isEmpty ? [] : [Group(title: String(format: "Results for “%@”".localized, query), entries: shown)])

        rebuildCards(highlight: query, flat: !lowered.isEmpty)

        let empty = shown.isEmpty
        emptyView.isHidden = !empty
        fadeView.isHidden = empty
        scrollView.isHidden = empty
        if empty {
            if entries.isEmpty {
                emptyView.configure(icon: "HistoryFocus", heading: "No previews yet".localized,
                                    detail: "Select a file path or image link anywhere and use your Glance shortcut.\nEverything you preview shows up here.".localized)
            } else {
                emptyView.configure(icon: "HistorySearch", heading: "No matches".localized,
                                    detail: "Try a different filename or filter.".localized)
            }
        }
        layoutGrid()
    }

    private static func dayGroups(for entries: [HistoryEntry]) -> [Group] {
        let calendar = Calendar.current
        var today: [HistoryEntry] = [], yesterday: [HistoryEntry] = [], earlier: [HistoryEntry] = []
        for entry in entries {
            if calendar.isDateInToday(entry.timestamp) { today.append(entry) }
            else if calendar.isDateInYesterday(entry.timestamp) { yesterday.append(entry) }
            else { earlier.append(entry) }
        }
        return [Group(title: "Today".localized, entries: today),
                Group(title: "Yesterday".localized, entries: yesterday),
                Group(title: "Earlier".localized, entries: earlier)].filter { !$0.entries.isEmpty }
    }

    // MARK: Cards

    private func rebuildCards(highlight: String, flat: Bool) {
        headers.forEach { $0.removeFromSuperview() }
        cards.forEach { $0.removeFromSuperview() }
        headers.removeAll(); cards.removeAll()

        for group in groups {
            let header = HistorySectionHeader(title: group.title, count: group.entries.count)
            gridDocView.addSubview(header)
            headers.append(header)
            for entry in group.entries {
                let card = HistoryCardView(entry: entry, highlight: highlight,
                                           meta: metaText(for: entry, flat: flat))
                card.onOpen = { [weak self] in self?.handleTileTap(info: entry.info) }
                card.onReveal = { NSWorkspace.shared.activateFileViewerSelecting([entry.info.url]) }
                card.onRemove = { HistoryManager.shared.remove(value: entry.storedValue) }
                gridDocView.addSubview(card)
                cards.append(card)
                loadThumbnail(for: entry.info, card: card)
                loadExtras(for: entry, card: card, flat: flat)
            }
        }
    }

    private func layoutGrid() {
        var contentW = scrollView.contentSize.width
        if contentW <= 0 { contentW = scrollView.frame.width }
        guard contentW > 0 else { return }

        let avail = contentW - Metric.margin * 2
        let cols = max(1, Int((avail + Metric.cardGap) / (Metric.minCardW + Metric.cardGap)))
        let cardW = floor((avail - Metric.cardGap * CGFloat(cols - 1)) / CGFloat(cols))
        let cardH = HistoryCardView.height(forWidth: cardW)

        var y = Metric.docTopPad
        var headerIndex = 0, cardIndex = 0
        for group in groups {
            headers[headerIndex].frame = NSRect(x: Metric.margin, y: y, width: avail, height: 20)
            headerIndex += 1
            y += Metric.sectionToCards
            let rows = (group.entries.count + cols - 1) / cols
            for i in 0..<group.entries.count {
                let row = i / cols, col = i % cols
                cards[cardIndex].frame = NSRect(x: Metric.margin + CGFloat(col) * (cardW + Metric.cardGap),
                                                y: y + CGFloat(row) * (cardH + Metric.rowGap),
                                                width: cardW, height: cardH)
                cardIndex += 1
            }
            y += CGFloat(rows) * cardH + CGFloat(max(0, rows - 1)) * Metric.rowGap + Metric.afterRow
        }
        gridDocView.frame = NSRect(x: 0, y: 0, width: contentW,
                                   height: max(y + 60, scrollView.contentSize.height))
    }

    // MARK: Thumbnails and metadata

    private func loadThumbnail(for info: MediaInfo, card: HistoryCardView) {
        let key = info.url.absoluteString as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            card.setThumbnail(cached)
            return
        }
        switch info.kind {
        case .image:
            if info.isLocal {
                let url = info.url
                DispatchQueue.global(qos: .userInitiated).async { [weak self, weak card] in
                    let image = Self.downsampledImage(at: url)
                    DispatchQueue.main.async {
                        if let image { self?.thumbnailCache.setObject(image, forKey: key); card?.setThumbnail(image) }
                        else { self?.loadFullImage(info, key: key, card: card) }
                    }
                }
            } else {
                loadFullImage(info, key: key, card: card)
            }
        case .video:
            imageLoader.loadVideoThumbnail(from: info.url) { [weak self, weak card] image in
                DispatchQueue.main.async {
                    guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                    self?.thumbnailCache.setObject(cg, forKey: key)
                    card?.setThumbnail(cg)
                }
            }
        default:
            card.setDocument()
        }
    }

    private func loadFullImage(_ info: MediaInfo, key: NSString, card: HistoryCardView?) {
        imageLoader.loadImage(from: info.url) { [weak self, weak card] image in
            DispatchQueue.main.async {
                guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { card?.setFailed(); return }
                self?.thumbnailCache.setObject(cg, forKey: key)
                card?.setThumbnail(cg)
            }
        }
    }

    private static func downsampledImage(at url: URL, maxPixel: Int = 720) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// File size (local files) and video duration arrive after the card exists,
    /// so building the list never touches the disk on the main thread.
    private func loadExtras(for entry: HistoryEntry, card: HistoryCardView, flat: Bool) {
        let info = entry.info
        let path = info.url.path
        if info.isLocal {
            if let cached = sizeCache[path] {
                card.setMeta(metaText(for: entry, flat: flat, size: cached))
            } else {
                DispatchQueue.global(qos: .utility).async { [weak self, weak card] in
                    guard let bytes = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 else { return }
                    let text = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.sizeCache[path] = text
                        card?.setMeta(self.metaText(for: entry, flat: flat, size: text))
                    }
                }
            }
        }
        if info.kind == .video, info.isLocal {
            if let cached = durationCache[path] { card.setDuration(cached); return }
            let url = info.url
            Task.detached { [weak self, weak card] in
                guard let time = try? await AVURLAsset(url: url).load(.duration), time.seconds.isFinite, time.seconds > 0 else { return }
                let text = Self.durationText(time.seconds)
                await MainActor.run {
                    self?.durationCache[path] = text
                    card?.setDuration(text)
                }
            }
        }
    }

    private static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func metaText(for entry: HistoryEntry, flat: Bool, size: String? = nil) -> String {
        var parts = [Self.formatName(for: entry.info)]
        if let size = size ?? sizeCache[entry.info.url.path] { parts.append(size) }
        parts.append(timeText(for: entry.timestamp, flat: flat))
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func formatName(for info: MediaInfo) -> String {
        switch info.formatName {
        case "JPG", "JPEG": return "JPEG"
        case "WEBP": return "WebP"
        case "MD", "MARKDOWN": return "Markdown"
        case "": return info.kind == .webPage ? (info.url.host ?? "") : ""
        case let other: return other
        }
    }

    /// Day groups already say Today / Yesterday, so cards show the time there
    /// and the date in "Earlier". A flat search list needs the day spelled out.
    private func timeText(for date: Date, flat: Bool) -> String {
        let locale = Locale(identifier: Preferences.shared.appLanguage.rawValue)
        let calendar = Calendar.current
        let time = DateFormatter()
        time.locale = locale; time.timeStyle = .short; time.dateStyle = .none
        let day = DateFormatter()
        day.locale = locale
        day.setLocalizedDateFormatFromTemplate("MMMd")
        if calendar.isDateInToday(date) {
            return flat ? "Today".localized + " " + time.string(from: date) : time.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return flat ? "Yesterday".localized : time.string(from: date)
        }
        return day.string(from: date)
    }

    // MARK: Actions

    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }

    /// Images and videos reopen inside Glance (Image / Video Inspect). Falls
    /// back to the system app only when nobody wired the callback.
    var onOpenMedia: ((MediaInfo) -> Void)?

    private func handleTileTap(info: MediaInfo) {
        switch info.kind {
        case .image, .video:
            if let onOpenMedia { onOpenMedia(info) } else { NSWorkspace.shared.open(info.url) }
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

    private func clearTapped() {
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
        DispatchQueue.main.async { [weak self] in self?.rebuildEntries() }
    }

    @objc private func languageChanged() {
        titlebar.title = "Preview History".localized
        searchBox.updatePlaceholder()
        applyFilter()
    }

    func windowDidResize(_ notification: Notification) { layoutContent() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            searchBox.focus()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
