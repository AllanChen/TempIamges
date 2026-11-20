import AppKit
import AVKit

/// Widget Market, built from Figma `09 · Widget Market` (Glance · Shizuka): a
/// catalog column (search, Market / Installed / Updates tabs with counts, widget
/// rows) beside a detail column (eyebrow, Mincho title, actions, description,
/// spec rows). The root view is flipped so board coordinates are used as drawn.
final class WidgetMarketPanel: NSPanel {
    /// Recreated on language change: every label is set when the panel is built.
    private(set) static var shared = WidgetMarketPanel()

    static func discardForLanguageChange() {
        let old = shared
        old.detachFromParent()
        old.close()
        NotificationCenter.default.removeObserver(old)
        shared = WidgetMarketPanel()
    }

    private enum CatalogFilter: Int { case marketplace, installed, updates }
    // Board geometry (top-origin; the root view is flipped).
    private static let designSize = NSSize(width: 1440, height: 900)
    private static let columnX: CGFloat = 16
    private static let columnWidth: CGFloat = 388
    private static let dividerX: CGFloat = 420
    private static let rowHeight: CGFloat = 56
    private static let listTop: CGFloat = 144

    private weak var attachedParent: NSWindow?
    private var isRaising = false
    private var manifests: [WidgetManifest] = []
    private var catalogIDs = Set<String>()
    private var installedIDs = Set<String>()
    private var isLoading = false
    private var hasAttemptedLoad = false
    private var hasFinishedLoad = false
    private var catalogLoadFailed = false
    private var selectedWidgetID: String?
    private var detailView: WidgetMarketDetailView?
    private var detailWidgetID: String?
    private var catalogFilter: CatalogFilter = .marketplace
    private var sortsByName = false

    private let rootView = WidgetMarketRootView()
    private let dragRegion = WidgetMarketDragRegion()
    private let closeTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1))
    private let minimizeTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1))
    private let zoomTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1))
    private let titleLabel = WidgetMarketTextView(labelWithString: "Widgets".localized)
    private lazy var refreshButton = WidgetMarketIconButton(icon: "TaskIconRefresh", tooltip: "Refresh".localized) { [weak self] in self?.refreshTapped() }
    private let columnDivider = NSView()
    private let searchBox = WidgetMarketSearchField()
    private let tabs = WidgetMarketTabBar(titles: ["Marketplace".localized, "Installed".localized, "Updates".localized])
    private lazy var sortButton = WidgetMarketIconButton(icon: "MarketIconSort", tooltip: "Sort by name".localized) { [weak self] in self?.sortTapped() }
    private let scrollView = NSScrollView()
    private let catalogContainer = WidgetMarketListDocumentView()
    private let scrollIndicator = GlanceScrollIndicator(axis: .vertical)
    private let emptyIcon = NSImageView()
    private let emptyTitle = WidgetMarketTextView(labelWithString: "")
    private let emptyHint = WidgetMarketTextView(labelWithString: "")
    private let loadingOverlay = WidgetMarketListDocumentView()
    private let loadingLabel = WidgetMarketTextView(labelWithString: "Loading…".localized)
    private let loadingSpinner = WidgetMarketLoadingIndicator()

    private init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.designSize),
                   styleMask: [.borderless, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 900, height: 600)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = PanelStyle.windowAppearance
        animationBehavior = .none
        buildUI()
        refreshInstalledState()
        NotificationCenter.default.addObserver(self, selector: #selector(registryDidChange),
                                               name: WidgetRegistry.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeKey),
                                               name: NSWindow.didBecomeKeyNotification, object: self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func toggle(from parent: NSWindow) {
        if isVisible, attachedParent === parent { close(); return }
        detachFromParent()
        attachedParent = parent
        NotificationCenter.default.addObserver(self, selector: #selector(parentGeometryDidChange),
                                               name: NSWindow.didMoveNotification, object: parent)
        NotificationCenter.default.addObserver(self, selector: #selector(parentGeometryDidChange),
                                               name: NSWindow.didResizeNotification, object: parent)
        position(alongside: parent)
        parent.addChildWindow(self, ordered: .above)
        if !hasAttemptedLoad { loadCatalog() }
        else if !isLoading { refreshFromServer(showLoading: false) }
        makeKeyAndOrderFront(nil)
        (detailView?.demoView as? NSImageView)?.animates = true
    }

    override func close() {
        (detailView?.demoView as? AVPlayerView)?.player?.pause()
        (detailView?.demoView as? NSImageView)?.animates = false
        detachFromParent()
        orderOut(nil)
    }

    private func detachFromParent() {
        guard let attachedParent else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification,
                                                   object: attachedParent)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification,
                                                   object: attachedParent)
        attachedParent.removeChildWindow(self)
        self.attachedParent = nil
    }

    @objc private func parentGeometryDidChange(_ notification: Notification) {
        guard let attachedParent else { return }
        position(alongside: attachedParent)
    }

    @objc private func didBecomeKey(_ notification: Notification) {
        guard !isRaising, let attachedParent else { return }
        isRaising = true
        defer { isRaising = false }
        attachedParent.removeChildWindow(self)
        attachedParent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    // MARK: Catalog data

    private func loadCatalog() {
        guard !hasAttemptedLoad else { return }
        hasAttemptedLoad = true
        // The server owns the catalog, including removal of former built-ins.
        // Keep installed entries available offline without inventing catalog rows.
        catalogIDs = []
        manifests = Self.mergeInstalled(into: [])
        refreshFromServer(showLoading: true)
    }

    private func refreshFromServer(showLoading: Bool) {
        guard !isLoading else { return }
        isLoading = true
        catalogLoadFailed = false
        setLoading(showLoading || catalogIDs.isEmpty)
        refreshCatalog(resetScroll: false)
        WidgetCatalogClient.shared.fetchAll { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            self.hasFinishedLoad = true
            self.setLoading(false)
            switch result {
            case .success(let catalog):
                let remoteManifests = catalog.widgets
                Logger.info("WidgetMarketPanel: refreshed \(remoteManifests.count) widgets from server")
                // Hide installed Widgets the service has taken down before
                // merging, so they disappear from the Installed tab too.
                WidgetAvailabilitySync.shared.apply(catalog)
                self.catalogIDs = Set(remoteManifests.map(\.id))
                self.manifests = Self.mergeInstalled(into: remoteManifests)
            case .failure(let error):
                self.catalogLoadFailed = true
                Logger.info("WidgetMarketPanel: catalog fetch failed: \(error.localizedDescription)")
            }
            self.refreshCatalog(resetScroll: true)
        }
    }

    private static func mergeInstalled(into catalog: [WidgetManifest]) -> [WidgetManifest] {
        var merged = catalog
        let known = Set(catalog.map(\.id))
        merged.append(contentsOf: WidgetRegistry.shared.available.filter { !known.contains($0.id) })
        return merged
    }

    private func refreshInstalledState() {
        installedIDs = Set(WidgetRegistry.shared.available.map(\.id))
        if hasAttemptedLoad {
            manifests = Self.mergeInstalled(into: manifests)
        }
        refreshCatalog(resetScroll: false)
    }

    private var updatesAvailable: Set<String> {
        var result = Set<String>()
        for remote in manifests {
            guard catalogIDs.contains(remote.id) else { continue }
            guard let local = WidgetRegistry.shared.installed.first(where: { $0.id == remote.id }) else { continue }
            if local.version != remote.version || local.commands != remote.commands ||
                local.name != remote.name || local.summary != remote.summary ||
                local.localizations != remote.localizations ||
                local.author != remote.author || local.iconURL != remote.iconURL ||
                local.taskCreditCost != remote.taskCreditCost || local.billing != remote.billing ||
                local.privacy.notice != remote.privacy.notice {
                result.insert(remote.id)
            }
        }
        return result
    }

    private var visibleManifests: [WidgetManifest] {
        let query = searchBox.query
        let updates = updatesAvailable
        var result = manifests.filter { manifest in
            switch catalogFilter {
            case .marketplace: guard catalogIDs.contains(manifest.id) else { return false }
            case .installed: guard installedIDs.contains(manifest.id) else { return false }
            case .updates: guard updates.contains(manifest.id) else { return false }
            }
            guard !query.isEmpty else { return true }
            return manifest.searchableText.localizedCaseInsensitiveContains(query)
        }
        if sortsByName {
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return result
    }

    @objc private func registryDidChange() { refreshInstalledState() }

    // MARK: Chrome

    private func buildUI() {
        contentView = rootView
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surface)
        rootView.layer?.cornerRadius = PanelStyle.Radius.window
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.borderWidth = 1
        rootView.layer?.borderColor = PanelStyle.resolvedCG(WidgetMarketTone.lineStrong)
        rootView.layer?.masksToBounds = true
        rootView.onLayout = { [weak self] bounds in self?.layoutContent(in: bounds) }

        // Board: 44 pt drag region, traffic lights at (20, 16), centred title, refresh at the right.
        rootView.addSubview(dragRegion)
        [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].forEach { rootView.addSubview($0) }
        closeTrafficButton.target = self; closeTrafficButton.action = #selector(closeTapped)
        minimizeTrafficButton.target = self; minimizeTrafficButton.action = #selector(minimizeTapped)
        zoomTrafficButton.target = self; zoomTrafficButton.action = #selector(zoomTapped)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = PanelStyle.textSecondary
        titleLabel.alignment = .center
        rootView.addSubview(titleLabel)
        rootView.addSubview(refreshButton)
        columnDivider.wantsLayer = true
        columnDivider.layer?.backgroundColor = PanelStyle.resolvedCG(WidgetMarketTone.line)
        rootView.addSubview(columnDivider)

        searchBox.onChange = { [weak self] in self?.refreshCatalog(resetScroll: true) }
        rootView.addSubview(searchBox)
        tabs.onSelect = { [weak self] index in self?.filterTapped(index) }
        rootView.addSubview(tabs)
        rootView.addSubview(sortButton)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = catalogContainer
        scrollView.contentView.postsBoundsChangedNotifications = true
        rootView.addSubview(scrollView)
        scrollIndicator.setAccessibilityLabel("Scroll widgets".localized)
        scrollIndicator.onSeek = { [weak self] fraction in
            guard let self else { return }
            let overflow = max(0, self.catalogContainer.bounds.height - self.scrollView.contentView.bounds.height)
            self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: fraction * overflow))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
        rootView.addSubview(scrollIndicator)
        NotificationCenter.default.addObserver(self, selector: #selector(listBoundsDidChange),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        // Empty search: the search glyph, a title and a hint, grouped by space rather than a box.
        emptyIcon.image = HistoryStyle.icon("HistorySearch", color: PanelStyle.textTertiary, size: 28)
        emptyIcon.imageScaling = .scaleProportionallyUpOrDown
        rootView.addSubview(emptyIcon)
        emptyTitle.font = PanelStyle.inspectFont(ofSize: 14, weight: .medium)
        emptyTitle.textColor = PanelStyle.textPrimary
        emptyTitle.alignment = .center
        emptyHint.font = PanelStyle.inspectFont(ofSize: 12)
        emptyHint.textColor = PanelStyle.textTertiary
        emptyHint.alignment = .center
        emptyHint.maximumNumberOfLines = 2
        emptyHint.lineBreakMode = .byWordWrapping
        rootView.addSubview(emptyTitle)
        rootView.addSubview(emptyHint)

        loadingOverlay.wantsLayer = true
        loadingOverlay.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surface)
        loadingOverlay.addSubview(loadingSpinner)
        loadingLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        loadingLabel.textColor = PanelStyle.textSecondary
        loadingLabel.alignment = .center
        loadingOverlay.addSubview(loadingLabel)
        rootView.addSubview(loadingOverlay)
        setLoading(false)
        layoutContent(in: rootView.bounds)
    }

    /// Board coordinates are top-origin on a 1440 × 900 board; the root is
    /// flipped, so frames are written as drawn. The catalog column keeps its
    /// board width and the detail column takes the remaining width.
    private func layoutContent(in bounds: NSRect) {
        let width = bounds.width, height = bounds.height
        let x = Self.columnX, columnWidth = Self.columnWidth
        dragRegion.frame = NSRect(x: 0, y: 0, width: width, height: 44)
        [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].enumerated().forEach { index, button in
            button.frame = NSRect(x: 20 + CGFloat(index) * 20, y: 16, width: 12, height: 12)
        }
        titleLabel.frame = NSRect(x: 100, y: 14, width: max(0, width - 200), height: 16)
        refreshButton.frame = NSRect(x: width - 48, y: 8, width: 28, height: 28)
        columnDivider.frame = NSRect(x: Self.dividerX, y: 44, width: 1, height: max(0, height - 44))

        searchBox.frame = NSRect(x: x, y: 60, width: columnWidth, height: 34)
        tabs.frame = NSRect(x: x, y: 110, width: columnWidth - 40, height: 22)
        sortButton.frame = NSRect(x: x + columnWidth - 28, y: 107, width: 28, height: 28)

        let listBottom = height - 16
        let listHeight = max(0, listBottom - Self.listTop)
        scrollView.frame = NSRect(x: x, y: Self.listTop, width: columnWidth, height: listHeight)
        catalogContainer.frame.size.width = columnWidth
        for row in catalogContainer.subviews { row.frame.size.width = columnWidth }
        scrollIndicator.frame = NSRect(x: x + columnWidth + 2, y: Self.listTop + 8, width: 12,
                                       height: max(0, listHeight - 16))

        emptyIcon.frame = NSRect(x: x + (columnWidth - 28) / 2, y: 300, width: 28, height: 28)
        emptyTitle.frame = NSRect(x: x, y: 344, width: columnWidth, height: 18)
        emptyHint.frame = NSRect(x: x + 24, y: 368, width: columnWidth - 48, height: 32)

        loadingOverlay.frame = NSRect(x: x, y: Self.listTop, width: columnWidth, height: listHeight)
        let spinnerSize: CGFloat = 20
        loadingSpinner.frame = NSRect(x: (columnWidth - spinnerSize) / 2,
            y: loadingOverlay.bounds.height / 2 - 28, width: spinnerSize, height: spinnerSize)
        loadingLabel.frame = NSRect(x: 0, y: loadingOverlay.bounds.height / 2 + 8, width: columnWidth, height: 16)
        detailView?.frame = NSRect(x: Self.dividerX + 1, y: 44, width: max(0, width - Self.dividerX - 1),
                                   height: max(0, height - 44))
        updateScrollIndicator()
    }

    private func refreshCatalog(resetScroll: Bool) {
        catalogContainer.subviews.forEach { $0.removeFromSuperview() }
        let visible = visibleManifests
        let updates = updatesAvailable
        if !visible.contains(where: { $0.id == selectedWidgetID }) { selectedWidgetID = visible.first?.id }
        let contentHeight = CGFloat(visible.count) * Self.rowHeight
        let rowWidth = max(0, scrollView.frame.width)
        catalogContainer.frame = NSRect(x: 0, y: 0, width: rowWidth, height: max(scrollView.contentSize.height, contentHeight))
        for (index, manifest) in visible.enumerated() {
            let row = WidgetMarketRowView(manifest: manifest,
                isInstalled: installedIDs.contains(manifest.id), hasUpdate: updates.contains(manifest.id),
                isRemovedFromCatalog: !catalogIDs.contains(manifest.id))
            row.frame = NSRect(x: 0, y: CGFloat(index) * Self.rowHeight, width: rowWidth, height: Self.rowHeight)
            row.isSelected = manifest.id == selectedWidgetID
            row.onInstall = { [weak self] in self?.install(manifest) }
            row.onShowDetails = { [weak self] in self?.showDetails(manifest) }
            catalogContainer.addSubview(row)
        }
        searchBox.placeholder = isLoading && catalogIDs.isEmpty ? "Search widgets".localized : String(format: "Search %d widgets".localized, catalogIDs.count)
        tabs.showsCounts = !isLoading || !catalogIDs.isEmpty
        tabs.counts = [catalogIDs.count, installedIDs.count, updates.count]
        tabs.selectedSegment = catalogFilter.rawValue
        let none = visible.isEmpty
        scrollView.isHidden = none
        let showEmpty = none && !isLoading && hasFinishedLoad
        [emptyIcon, emptyTitle, emptyHint].forEach { $0.isHidden = !showEmpty }
        if showEmpty {
            let searching = !searchBox.query.isEmpty
            emptyTitle.stringValue = catalogLoadFailed ? "Could not load widgets".localized : searching ? "No matching widgets".localized : "No widgets available".localized
            emptyHint.stringValue = !catalogLoadFailed && searching ? "Try a different search, or clear it to see every widget.".localized
                                              : "Refresh to load the catalog.".localized
        }
        if resetScroll { scrollView.contentView.scroll(to: .zero) }
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateScrollIndicator()
        refreshDetail()
    }

    private func updateScrollIndicator() {
        let scrollable = catalogContainer.frame.height > scrollView.contentView.bounds.height + 1
        scrollIndicator.update(contentLength: catalogContainer.frame.height,
            viewportLength: scrollView.contentView.bounds.height, offset: scrollView.contentView.bounds.minY)
        scrollIndicator.isHidden = scrollView.isHidden || !scrollable
    }

    private func setLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
        loadingSpinner.setAnimating(loading)
    }

    private func showDetails(_ manifest: WidgetManifest) {
        selectedWidgetID = manifest.id
        for case let row as WidgetMarketRowView in catalogContainer.subviews {
            row.isSelected = row.widgetID == manifest.id
        }
        refreshDetail()
    }

    private func refreshDetail() {
        guard let selectedWidgetID, let manifest = manifests.first(where: { $0.id == selectedWidgetID }) else {
            detailView?.removeFromSuperview()
            detailView = nil
            detailWidgetID = nil
            return
        }
        let previousOffset = detailWidgetID == selectedWidgetID ? detailView?.scrollOffset : nil
        let previousDemo = detailWidgetID == selectedWidgetID ? detailView?.demoView : nil
        detailView?.removeFromSuperview()
        let detail = WidgetMarketDetailView(manifest: manifest,
            isInstalled: installedIDs.contains(manifest.id), hasUpdate: updatesAvailable.contains(manifest.id),
            isAvailable: catalogIDs.contains(manifest.id), previousDemo: previousDemo)
        detail.onInstall = { [weak self] in self?.install(manifest) }
        detail.onRemove = { WidgetRegistry.shared.uninstall(id: manifest.id) }
        detail.onRun = {
            // Run the installed copy: it is the version the service will price.
            let installed = WidgetRegistry.shared.available.first(where: { $0.id == manifest.id }) ?? manifest
            guard let command = installed.commands.first(where: \.isTextOnly) else { return }
            TextWidgetPanel.present(widget: installed, command: command)
        }
        detailView = detail
        detailWidgetID = selectedWidgetID
        rootView.addSubview(detail, positioned: .below, relativeTo: loadingOverlay)
        layoutContent(in: rootView.bounds)
        detail.layoutSubtreeIfNeeded()
        if let previousOffset { detail.restoreScrollOffset(previousOffset) }
    }

    private func filterTapped(_ index: Int) {
        guard let filter = CatalogFilter(rawValue: index), filter != catalogFilter else { return }
        catalogFilter = filter
        refreshCatalog(resetScroll: true)
    }

    private func sortTapped() {
        sortsByName.toggle()
        sortButton.isActive = sortsByName
        refreshCatalog(resetScroll: true)
    }

    @objc private func listBoundsDidChange() { updateScrollIndicator() }
    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }
    private func refreshTapped() { hasAttemptedLoad = true; refreshFromServer(showLoading: true) }

    private func install(_ manifest: WidgetManifest) {
        WidgetCatalogClient.shared.fetch(widgetID: manifest.id) { result in
            switch result {
            case .success(let fullManifest): WidgetRegistry.shared.install(fullManifest)
            case .failure(let error): Logger.info("WidgetMarketPanel: install failed: \(error.localizedDescription)")
            }
        }
    }

    private func position(alongside parent: NSWindow) {
        let gap: CGFloat = 2
        let visibleFrame = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let size = NSSize(width: min(Self.designSize.width, visibleFrame.width),
                          height: min(Self.designSize.height, visibleFrame.height))
        let x = max(visibleFrame.minX,
                    min(parent.frame.maxX + gap, visibleFrame.maxX - size.width))
        let y = max(visibleFrame.minY,
                    min(parent.frame.maxY - size.height, visibleFrame.maxY - size.height))
        let proposed = NSRect(x: x, y: y, width: size.width, height: size.height)
        if frame != proposed { setFrame(proposed, display: true) }
    }
}

// MARK: - Layout and chrome

/// Shizuka tokens the shared palette does not name.
private enum WidgetMarketTone {
    static let line = PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line)
    static let lineStrong = PanelStyle.themed(PanelStyle.Sumi.lineStrong, PanelStyle.Washi.lineStrong)
    static let ink3 = PanelStyle.themed(PanelStyle.Sumi.ink3, PanelStyle.Washi.ink3)
    static let text4 = PanelStyle.themed(PanelStyle.Sumi.text4, PanelStyle.Washi.text4)

    static func textWidth(_ string: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
    }

    /// "Free", the duration rate, or "n credit(s)": the price a row states.
    static func price(_ manifest: WidgetManifest) -> String {
        if manifest.taskCreditCost == 0 { return "Free".localized }
        if manifest.usesDurationBilling { return manifest.creditCostLabel }
        return String(format: (manifest.taskCreditCost == 1 ? "%d credit" : "%d credits").localized, manifest.taskCreditCost)
    }
}

/// Flipped so the board's top-origin coordinates can be used as written.
private final class WidgetMarketRootView: NSView {
    var onLayout: ((NSRect) -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?(bounds) }
}

/// Board "traffic" strip: moves the panel, double-click zooms.
private final class WidgetMarketDragRegion: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) }
        else { window?.performDrag(with: event) }
    }
}

private final class WidgetMarketListDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// A read-only Figma text slot. Drawing into its own bounds avoids the cell
/// insets of NSTextField changing the specified x/y position or wrapping width.
private final class WidgetMarketTextView: NSView {
    var stringValue: String { didSet { setAccessibilityLabel(stringValue); needsDisplay = true } }
    var font = PanelStyle.inspectFont(ofSize: 13) { didSet { needsDisplay = true } }
    var textColor = PanelStyle.textSecondary { didSet { needsDisplay = true } }
    var alignment: NSTextAlignment = .left { didSet { needsDisplay = true } }
    var lineBreakMode: NSLineBreakMode = .byTruncatingTail { didSet { needsDisplay = true } }
    var maximumNumberOfLines = 1 { didSet { needsDisplay = true } }
    var lineHeight: CGFloat? { didSet { needsDisplay = true } }
    var kern: CGFloat = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    init(labelWithString string: String) {
        stringValue = string
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(string)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var attributedText: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        if let lineHeight { paragraph.minimumLineHeight = lineHeight; paragraph.maximumLineHeight = lineHeight }
        return NSAttributedString(string: stringValue,
            attributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph, .kern: kern])
    }

    func fittingTextHeight(width: CGFloat) -> CGFloat {
        ceil(attributedText.boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    override func draw(_ dirtyRect: NSRect) {
        var rect = bounds
        if maximumNumberOfLines > 0 {
            let line = lineHeight ?? NSLayoutManager().defaultLineHeight(for: font)
            rect.size.height = min(rect.height, line * CGFloat(maximumNumberOfLines))
        }
        attributedText.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
    }
}

/// 28 pt icon button (refresh, sort): no plate at rest, ink/3 when toggled on.
private final class WidgetMarketIconButton: NSView {
    var isActive = false { didSet { needsDisplay = true; setAccessibilityValue(isActive) } }
    private let icon: String
    private let onClick: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(icon: String, tooltip: String, onClick: @escaping () -> Void) {
        self.icon = icon
        self.onClick = onClick
        super.init(frame: .zero)
        toolTip = tooltip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }

    override func draw(_ dirtyRect: NSRect) {
        if isActive || hovering {
            (isActive ? WidgetMarketTone.ink3 : PanelStyle.rowHover).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: PanelStyle.Radius.control, yRadius: PanelStyle.Radius.control).fill()
        }
        HistoryStyle.drawIcon(icon, color: isActive || hovering ? PanelStyle.textPrimary : PanelStyle.textSecondary,
                              in: CGRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16))
    }
}

/// Board "search field" (388 × 34, radius 6): glyph at (11, 9), text at x 35,
/// a clear control while there is a query; Escape clears, then leaves the field.
private final class WidgetMarketSearchField: NSView, NSTextFieldDelegate {
    var onChange: (() -> Void)?
    var placeholder = "Search widgets".localized { didSet { updatePlaceholder() } }
    private let field = HistoryTextField()
    private var focused = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var query: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = PanelStyle.textPrimary
        field.font = PanelStyle.inspectFont(ofSize: 13)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.onFocusChange = { [weak self] in self?.focused = $0 }
        addSubview(field)
        updatePlaceholder()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updatePlaceholder() {
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 13), .foregroundColor: PanelStyle.textTertiary])
    }

    private var clearRect: CGRect { CGRect(x: bounds.width - 26, y: 8, width: 18, height: 18) }

    override func layout() {
        super.layout()
        field.frame = CGRect(x: 35, y: (bounds.height - 18) / 2, width: max(0, bounds.width - 35 - 32), height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: PanelStyle.Radius.control, yRadius: PanelStyle.Radius.control)
        PanelStyle.overlay.setFill(); path.fill()
        (focused ? WidgetMarketTone.lineStrong.blended(withFraction: 0.5, of: PanelStyle.textTertiary) ?? WidgetMarketTone.lineStrong
                 : WidgetMarketTone.line).setStroke()
        path.lineWidth = 1; path.stroke()
        HistoryStyle.drawIcon("HistorySearch", color: PanelStyle.textTertiary, in: CGRect(x: 11, y: 9, width: 16, height: 16))
        if !field.stringValue.isEmpty {
            HistoryStyle.drawIcon("HistoryClose", color: PanelStyle.textTertiary, in: clearRect.insetBy(dx: 3, dy: 3))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !field.stringValue.isEmpty, clearRect.insetBy(dx: -4, dy: -4).contains(point) { clear(); return }
        window?.makeFirstResponder(field)
    }

    private func clear() {
        field.stringValue = ""
        needsDisplay = true
        onChange?()
    }

    func controlTextDidChange(_ obj: Notification) {
        needsDisplay = true
        onChange?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if field.stringValue.isEmpty { window?.makeFirstResponder(nil) } else { clear() }
        return true
    }
}

/// Board "tabs": label 12, mono count, 18 pt between tabs; the selected tab
/// reads text/1 with a 1 pt underline at y 21, the others text/3.
private final class WidgetMarketTabBar: NSView {
    var onSelect: ((Int) -> Void)?
    var selectedSegment = 0 { didSet { needsDisplay = true; updateAccessibility() } }
    var counts: [Int] = [0, 0, 0] { didSet { needsDisplay = true; updateAccessibility() } }
    var showsCounts = true { didSet { needsDisplay = true } }
    private let titles: [String]
    private let labelFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
    private let countFont = PanelStyle.monoFont(ofSize: 10)
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func tabRects() -> [CGRect] {
        var x: CGFloat = 4
        return titles.indices.map { index in
            let labelWidth = WidgetMarketTone.textWidth(titles[index], font: labelFont)
            let countWidth = showsCounts ? 5 + WidgetMarketTone.textWidth(String(counts[safe: index] ?? 0), font: countFont) : 0
            defer { x += labelWidth + countWidth + 18 }
            return CGRect(x: x, y: 0, width: labelWidth + countWidth, height: 22)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, rect) in tabRects().enumerated() {
            let selected = index == selectedSegment
            let labelWidth = WidgetMarketTone.textWidth(titles[index], font: labelFont)
            NSAttributedString(string: titles[index], attributes: [
                .font: labelFont, .foregroundColor: selected ? PanelStyle.textPrimary : PanelStyle.textTertiary
            ]).draw(with: CGRect(x: rect.minX, y: 0, width: labelWidth + 1, height: 15), options: [.usesLineFragmentOrigin])
            if showsCounts {
                NSAttributedString(string: String(counts[safe: index] ?? 0), attributes: [
                    .font: countFont, .foregroundColor: selected ? PanelStyle.textTertiary : WidgetMarketTone.text4
                ]).draw(with: CGRect(x: rect.minX + labelWidth + 5, y: 2, width: rect.width, height: 14),
                        options: [.usesLineFragmentOrigin])
            }
            if selected {
                PanelStyle.textPrimary.setFill()
                CGRect(x: rect.minX, y: 21, width: rect.width, height: 1).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = tabRects().firstIndex(where: { $0.insetBy(dx: -9, dy: -4).contains(point) }) { onSelect?(index) }
    }

    private func updateAccessibility() {
        let title = titles[safe: selectedSegment] ?? ""
        setAccessibilityValue(showsCounts ? "\(title) \(counts[safe: selectedSegment] ?? 0)" : title)
    }
}

/// The loading specimen's exported 20 pt refresh glyph, animated without a
/// polling timer. Reduced-motion users retain the static glyph and loading text.
private final class WidgetMarketLoadingIndicator: NSView {
    private let glyph = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let image = HistoryStyle.icon("MarketIconLoading", color: PanelStyle.textSecondary, size: 20)
        glyph.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        glyph.contentsGravity = .resizeAspect
        layer?.addSublayer(glyph)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glyph.bounds = bounds
        glyph.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }
    func setAnimating(_ running: Bool) {
        glyph.removeAnimation(forKey: "loading")
        guard running, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = -Double.pi * 2
        rotation.duration = 1.1
        rotation.repeatCount = .infinity
        glyph.add(rotation, forKey: "loading")
    }
}

// MARK: - Catalog row

/// Board "widget row" (388 × 56): 36 pt tile at (12, 10); name 13 at (60, 11);
/// summary 12 text/3 at (60, 30); price in mono at the right edge, with the
/// installed / update state beneath it. Selected rows sit on ink/3. Hovering a
/// row that can be installed or updated swaps the price for that one action.
private final class WidgetMarketRowView: NSView {
    var onInstall: (() -> Void)?
    var onShowDetails: (() -> Void)?
    var isSelected = false { didSet { applyAppearance(); setAccessibilitySelected(isSelected) } }
    let widgetID: String
    private let isInstalled: Bool
    private let hasUpdate: Bool
    private let isRemovedFromCatalog: Bool
    private let iconTile = WidgetMarketIconTile()
    private let nameLabel = WidgetMarketTextView(labelWithString: "")
    private let summaryLabel = WidgetMarketTextView(labelWithString: "")
    private let priceLabel = WidgetMarketTextView(labelWithString: "")
    private let statusLabel = WidgetMarketTextView(labelWithString: "")
    private let action = WidgetMarketActionButton()
    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false
    override var isFlipped: Bool { true }

    init(manifest: WidgetManifest, isInstalled: Bool, hasUpdate: Bool, isRemovedFromCatalog: Bool) {
        widgetID = manifest.id
        self.isInstalled = isInstalled
        self.hasUpdate = hasUpdate
        self.isRemovedFromCatalog = isRemovedFromCatalog
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(manifest.displayName)
        buildUI(manifest)
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI(_ manifest: WidgetManifest) {
        iconTile.configure(monogram: Self.monogram(for: manifest), iconURL: manifest.iconURL)
        addSubview(iconTile)
        nameLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = PanelStyle.textPrimary
        nameLabel.stringValue = manifest.displayName
        summaryLabel.font = PanelStyle.inspectFont(ofSize: 12)
        summaryLabel.textColor = PanelStyle.textTertiary
        summaryLabel.stringValue = manifest.displaySummary
        priceLabel.font = PanelStyle.monoFont(ofSize: 11)
        priceLabel.textColor = PanelStyle.textSecondary
        priceLabel.alignment = .right
        priceLabel.stringValue = WidgetMarketTone.price(manifest)
        statusLabel.font = PanelStyle.inspectFont(ofSize: 11)
        statusLabel.alignment = .right
        if hasUpdate && !isRemovedFromCatalog {
            statusLabel.stringValue = "Update".localized
            statusLabel.textColor = PanelStyle.info
        } else if isInstalled || isRemovedFromCatalog {
            statusLabel.stringValue = "Installed".localized
            statusLabel.textColor = PanelStyle.success
        }
        for label in [nameLabel, summaryLabel, priceLabel, statusLabel] { addSubview(label) }
        nameLabel.toolTip = manifest.displayName
        summaryLabel.toolTip = manifest.displaySummary
        action.isCompact = true
        action.style = hasUpdate ? .update : .install
        action.target = self
        action.action = #selector(actionTapped)
        addSubview(action)
        updateAction()
    }

    /// Only a row that can still be installed or updated offers an action.
    private var offersAction: Bool { !isRemovedFromCatalog && (hasUpdate || !isInstalled) }

    private func updateAction() {
        let showAction = hovering && offersAction
        action.isHidden = !showAction
        priceLabel.isHidden = showAction
        statusLabel.isHidden = showAction
    }

    override func layout() {
        super.layout()
        iconTile.frame = NSRect(x: 12, y: 10, width: 36, height: 36)
        let hasStatus = !statusLabel.stringValue.isEmpty
        let rightWidth = min(140, max(WidgetMarketTone.textWidth(priceLabel.stringValue, font: priceLabel.font),
                                      hasStatus ? WidgetMarketTone.textWidth(statusLabel.stringValue, font: statusLabel.font) : 0))
        let rightX = bounds.width - 12 - rightWidth
        priceLabel.frame = NSRect(x: rightX, y: hasStatus ? 13 : 21, width: rightWidth, height: 14)
        statusLabel.frame = NSRect(x: rightX, y: 30, width: rightWidth, height: 13)
        let actionWidth = action.preferredWidth
        action.frame = NSRect(x: bounds.width - 12 - actionWidth, y: 14, width: actionWidth, height: 28)
        let textWidth = max(0, min(rightX, action.frame.minX) - 60 - 12)
        nameLabel.frame = NSRect(x: 60, y: 11, width: textWidth, height: 16)
        summaryLabel.frame = NSRect(x: 60, y: 30, width: textWidth, height: 15)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area); trackingAreaRef = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; applyAppearance(); updateAction() }
    override func mouseExited(with event: NSEvent) { hovering = false; applyAppearance(); updateAction() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return !action.isHidden && action.frame.contains(local) ? action : self
    }
    override func mouseDown(with event: NSEvent) { onShowDetails?() }
    override func accessibilityPerformPress() -> Bool { onShowDetails?(); return true }

    private func applyAppearance() {
        let fill: NSColor = isSelected ? WidgetMarketTone.ink3 : hovering ? PanelStyle.rowHover : .clear
        layer?.backgroundColor = PanelStyle.resolvedCG(fill)
    }

    @objc private func actionTapped() { onInstall?() }

    /// Two Latin letters from the English name (first letters of the first two
    /// words); a non-Latin name falls back to its first character.
    fileprivate static func monogram(for manifest: WidgetManifest) -> String {
        let source = manifest.localizations?["en"]?.name ?? manifest.name
        let words = source.split(separator: " ").filter { !$0.isEmpty }
        let letters: String
        if words.count > 1 { letters = words.prefix(2).compactMap(\.first).map(String.init).joined() }
        else { letters = String(source.prefix(2)) }
        if letters.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.letters.contains($0) }), !letters.isEmpty {
            return letters.uppercased()
        }
        return String(manifest.displayName.prefix(1))
    }
}

// MARK: - Detail column

/// Board "detail" (x 492, y 84 on the board; 72 pt right margin): eyebrow,
/// Mincho title with the actions on its baseline, author · version · state,
/// the description, then hairline-separated spec rows. Scrolls on its own.
private final class WidgetMarketDetailView: NSView {
    var onInstall: (() -> Void)?
    var onRemove: (() -> Void)?
    /// Opens the text Widget panel; shown for installed Widgets that run on text alone.
    var onRun: (() -> Void)?
    private static let leading: CGFloat = 71    // board x 492 − column x 421
    private static let top: CGFloat = 40        // board y 84 − 44
    private static let trailing: CGFloat = 72
    private let scrollView = NSScrollView()
    private let document = WidgetMarketListDocumentView(frame: NSRect(x: 0, y: 0, width: 876, height: 600))
    private let eyebrow = WidgetMarketTextView(labelWithString: "")
    private let titleLabel = WidgetMarketTextView(labelWithString: "")
    private let primaryAction = WidgetMarketActionButton()
    private let removeAction = WidgetMarketActionButton()
    private let runAction = WidgetMarketActionButton()
    private let authorLabel = WidgetMarketTextView(labelWithString: "")
    private let versionLabel = WidgetMarketTextView(labelWithString: "")
    private let stateIcon = NSImageView()
    private let stateLabel = WidgetMarketTextView(labelWithString: "")
    private let descriptionLabel = WidgetMarketTextView(labelWithString: "")
    private(set) var demoView: NSView?
    /// Spec rows: label, then the value views stacked in the value column.
    private var specRows: [(label: WidgetMarketTextView, values: [WidgetMarketTextView], gaps: [CGFloat])] = []
    private var specLines: [NSView] = []
    var scrollOffset: NSPoint { scrollView.contentView.bounds.origin }
    override var isFlipped: Bool { true }

    init(manifest: WidgetManifest, isInstalled: Bool, hasUpdate: Bool, isAvailable: Bool, previousDemo: NSView?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surface)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        PanelStyle.styleScrollers(in: scrollView)
        scrollView.borderType = .noBorder
        scrollView.documentView = document
        addSubview(scrollView)
        buildContent(manifest, isInstalled: isInstalled)
        if let previousDemo {
            demoView = previousDemo
            document.addSubview(previousDemo)
        } else if UUID(uuidString: manifest.id) != nil,
                  let url = (WidgetManifest.preferredLanguageTags.map { "\(manifest.id.lowercased())-\($0)" }
                             + [manifest.id.lowercased()]).lazy.compactMap({ name in
                      Bundle.main.url(forResource: name, withExtension: "gif", subdirectory: "WidgetDemos")
                  }).first {
            let view = NSImageView()
            view.imageScaling = .scaleProportionallyUpOrDown
            view.animates = true
            view.setAccessibilityLabel(manifest.displayName)
            demoView = view
            document.addSubview(view)
            DispatchQueue.global(qos: .userInitiated).async { [weak view] in
                let image = NSImage(contentsOf: url)
                DispatchQueue.main.async { view?.image = image }
            }
        } else if UUID(uuidString: manifest.id) != nil,
                  let url = WidgetManifest.preferredLanguageTags.lazy.compactMap({ tag in
                      Bundle.main.url(forResource: "\(manifest.id.lowercased())-\(tag)", withExtension: "mp4",
                                      subdirectory: "WidgetDemos")
                  }).first {
            let view = AVPlayerView()
            view.controlsStyle = .inline
            view.videoGravity = .resizeAspect
            view.player = AVPlayer(url: url)
            view.setAccessibilityLabel(manifest.displayName)
            document.addSubview(view)
            demoView = view
        }
        primaryAction.style = hasUpdate ? .update : .install
        primaryAction.target = self
        primaryAction.action = #selector(installTapped)
        primaryAction.isHidden = !isAvailable || (isInstalled && !hasUpdate)
        document.addSubview(primaryAction)
        removeAction.style = .remove
        removeAction.target = self
        removeAction.action = #selector(removeTapped)
        removeAction.isHidden = !isInstalled
        document.addSubview(removeAction)
        runAction.style = .run
        runAction.target = self
        runAction.action = #selector(runTapped)
        runAction.isHidden = !(isInstalled && isAvailable && manifest.hasTextOnlyCommand)
        document.addSubview(runAction)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func text(_ value: String, font: NSFont, color: NSColor, lines: Int = 1) -> WidgetMarketTextView {
        let view = WidgetMarketTextView(labelWithString: value)
        view.font = font
        view.textColor = color
        view.maximumNumberOfLines = lines
        view.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        view.toolTip = value
        document.addSubview(view)
        return view
    }

    private func buildContent(_ manifest: WidgetManifest, isInstalled: Bool) {
        let inputs = Set(manifest.commands.flatMap(\.inputTypes)).sorted().map { $0.capitalized.localized }.joined(separator: ", ")
        let outputs = Set(manifest.commands.flatMap(\.outputs)).sorted().map { $0.capitalized.localized }.joined(separator: ", ")
        for (view, value) in [(eyebrow, "\("Widget".localized)  ·  \(inputs) → \(outputs)".uppercased()),
                              (titleLabel, manifest.displayName), (authorLabel, manifest.author),
                              (versionLabel, "v\(manifest.version)"),
                              (stateLabel, (isInstalled ? "Installed" : "Not installed").localized),
                              (descriptionLabel, manifest.displaySummary)] {
            view.stringValue = value
            view.toolTip = value
            document.addSubview(view)
        }
        eyebrow.font = PanelStyle.monoFont(ofSize: 11)
        eyebrow.textColor = PanelStyle.textTertiary
        eyebrow.kern = 1.2
        titleLabel.font = PanelStyle.titleFont(ofSize: 30)
        titleLabel.textColor = PanelStyle.textPrimary
        authorLabel.font = PanelStyle.inspectFont(ofSize: 12)
        authorLabel.textColor = PanelStyle.textTertiary
        versionLabel.font = PanelStyle.monoFont(ofSize: 11)
        versionLabel.textColor = PanelStyle.textTertiary
        stateLabel.font = PanelStyle.inspectFont(ofSize: 12)
        stateLabel.textColor = isInstalled ? PanelStyle.success : PanelStyle.textTertiary
        stateIcon.image = HistoryStyle.icon("ToastCheck", color: PanelStyle.success, size: 16)
        stateIcon.imageScaling = .scaleProportionallyUpOrDown
        stateIcon.isHidden = !isInstalled
        document.addSubview(stateIcon)
        descriptionLabel.font = PanelStyle.inspectFont(ofSize: 14)
        descriptionLabel.textColor = PanelStyle.textSecondary
        descriptionLabel.lineHeight = 23
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping

        let valueFont = PanelStyle.inspectFont(ofSize: 13)
        func row(_ label: String, _ values: [WidgetMarketTextView], gaps: [CGFloat] = []) {
            let labelView = text(label, font: valueFont, color: PanelStyle.textTertiary)
            specRows.append((labelView, values, gaps))
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = PanelStyle.resolvedCG(WidgetMarketTone.line)
            document.addSubview(line)
            specLines.append(line)
        }
        func value(_ string: String, size: CGFloat = 13, color: NSColor = PanelStyle.textPrimary) -> WidgetMarketTextView {
            let view = text(string, font: PanelStyle.inspectFont(ofSize: size), color: color, lines: 0)
            return view
        }
        row("Input".localized, [value(inputs)])
        row("Output".localized, [value(outputs)])
        row("Cost per task".localized, [value(manifest.taskCreditCost == 0 ? "Free of charge".localized : manifest.creditCostLabel)])
        var commandViews: [WidgetMarketTextView] = []
        var commandGaps: [CGFloat] = []
        for (index, command) in manifest.localizedCommands.enumerated() {
            commandViews.append(value(command.name))
            commandGaps.append(index == 0 ? 0 : 12)
            commandViews.append(value(command.description, size: 12, color: PanelStyle.textSecondary))
            commandGaps.append(3)
        }
        if !commandViews.isEmpty { row("Commands".localized, commandViews, gaps: commandGaps) }
        row("Privacy".localized, [value(manifest.privacy.notice, color: PanelStyle.textSecondary)])
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let width = max(0, scrollView.contentSize.width)
        let x = Self.leading
        let contentWidth = max(240, width - x - Self.trailing)
        let right = x + contentWidth

        // Actions sit on the title's baseline row (board y 30, 32 tall), primary rightmost.
        var actionX = right
        for button in [runAction, primaryAction, removeAction] where !button.isHidden {
            let w = button.preferredWidth
            actionX -= w
            button.frame = NSRect(x: actionX, y: Self.top + 30, width: w, height: 32)
            actionX -= 8
        }
        eyebrow.frame = NSRect(x: x, y: Self.top, width: contentWidth, height: 14)
        titleLabel.frame = NSRect(x: x, y: Self.top + 24, width: max(0, actionX - x - 8), height: 38)

        let metaY = Self.top + 74
        let authorWidth = min(240, WidgetMarketTone.textWidth(authorLabel.stringValue, font: authorLabel.font))
        authorLabel.frame = NSRect(x: x, y: metaY, width: authorWidth, height: 15)
        authorLabel.isHidden = authorLabel.stringValue.isEmpty
        let versionX = authorLabel.isHidden ? x : x + authorWidth + 20
        let versionWidth = min(120, WidgetMarketTone.textWidth(versionLabel.stringValue, font: versionLabel.font))
        versionLabel.frame = NSRect(x: versionX, y: metaY, width: versionWidth, height: 14)
        let stateX = versionX + versionWidth + 20
        stateIcon.frame = NSRect(x: stateX, y: metaY, width: 16, height: 16)
        let stateTextX = stateIcon.isHidden ? stateX : stateX + 22
        stateLabel.frame = NSRect(x: stateTextX, y: metaY + 0.5, width: max(0, right - stateTextX), height: 15)

        let descriptionWidth = min(700, contentWidth)
        let descriptionHeight = descriptionLabel.fittingTextHeight(width: descriptionWidth)
        descriptionLabel.frame = NSRect(x: x, y: Self.top + 122, width: descriptionWidth, height: descriptionHeight)

        // Spec rows: label column 120, value at +132; 10 pt above and below; hairline under each row.
        var y = descriptionLabel.frame.maxY + 32
        if let demoView {
            demoView.frame = NSRect(x: x, y: descriptionLabel.frame.maxY + 16,
                                    width: descriptionWidth, height: descriptionWidth * 2 / 3)
            y = demoView.frame.maxY + 20
        }
        let valueX = x + 132
        let valueWidth = max(0, contentWidth - 132)
        for (index, row) in specRows.enumerated() {
            row.label.frame = NSRect(x: x, y: y + 10, width: 120, height: 16)
            var valueY = y + 10
            for (valueIndex, view) in row.values.enumerated() {
                valueY += row.gaps[safe: valueIndex] ?? 0
                let height = max(16, view.fittingTextHeight(width: valueWidth))
                view.frame = NSRect(x: valueX, y: valueY, width: valueWidth, height: height)
                valueY += height
            }
            let rowHeight = max(37, valueY + 10 - y)
            specLines[index].frame = NSRect(x: x, y: y + rowHeight - 1, width: contentWidth, height: 1)
            y += rowHeight
        }
        document.frame.size = NSSize(width: width, height: max(y + 40, scrollView.contentSize.height))
    }

    @objc private func installTapped() { onInstall?() }
    @objc private func removeTapped() { onRemove?() }
    @objc private func runTapped() { onRun?() }

    func restoreScrollOffset(_ offset: NSPoint) {
        let maxY = max(0, document.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, offset.y), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// Board icon frame (36 pt, radius 6, ink/2 with a hairline): a monogram,
/// replaced by the widget icon (aspect fill) once it loads.
private final class WidgetMarketIconTile: NSView {
    private static var iconCache: [URL: NSImage] = [:]
    private let monogramLabel = PanelCenteredTextView()
    private let iconLayer = CALayer()
    private var pendingURL: URL?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(WidgetMarketTone.line)
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.overlay)
        layer?.masksToBounds = true
        monogramLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        monogramLabel.textColor = PanelStyle.textSecondary
        addSubview(monogramLabel)
        iconLayer.contentsGravity = .resizeAspectFill
        iconLayer.masksToBounds = true
        iconLayer.isHidden = true
        layer?.addSublayer(iconLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(monogram: String, iconURL: URL?) {
        monogramLabel.string = monogram
        pendingURL = iconURL
        guard let iconURL, iconURL.scheme == "https" else { return }
        if let cached = Self.iconCache[iconURL] { show(cached); return }
        URLSession.shared.dataTask(with: iconURL) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                Self.iconCache[iconURL] = image
                guard let self, self.pendingURL == iconURL else { return }
                self.show(image)
            }
        }.resume()
    }

    private func show(_ image: NSImage) {
        iconLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        iconLayer.isHidden = false
        monogramLabel.isHidden = true
    }

    override func layout() {
        super.layout()
        monogramLabel.frame = bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        iconLayer.frame = bounds
        CATransaction.commit()
    }
}

/// Market action. Board "Button": 32 pt (28 in a row), radius 6, label 13
/// medium centred. install / update: accent fill with accent ink;
/// remove: quiet, a strong hairline with text/1.
private final class WidgetMarketActionButton: NSButton {
    enum Style {
        case install, update, remove, run
        var title: String {
            switch self {
            case .install: return "Install".localized
            case .update: return "Update".localized
            case .remove: return "Remove".localized
            case .run: return "Run".localized
            }
        }
        var isPrimary: Bool { self != .remove }
    }
    var style: Style = .install { didSet { applyAppearance() } }
    var isCompact = false { didSet { applyAppearance() } }
    private let titleView = PanelCenteredTextView()
    private var hovering = false { didSet { applyAppearance() } }

    var preferredWidth: CGFloat {
        WidgetMarketTone.textWidth(style.title, font: titleView.font) + (isCompact ? 24 : 32)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        addSubview(titleView)
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() { super.layout(); titleView.frame = bounds }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func applyAppearance() {
        titleView.string = style.title
        titleView.font = PanelStyle.inspectFont(ofSize: isCompact ? 12 : 13, weight: .medium)
        if style.isPrimary {
            titleView.textColor = PanelStyle.accentInk
            layer?.backgroundColor = PanelStyle.resolvedCG(hovering ? PanelStyle.accentHover : PanelStyle.accent)
            layer?.borderWidth = 0
        } else {
            titleView.textColor = PanelStyle.textPrimary
            layer?.backgroundColor = PanelStyle.resolvedCG(hovering ? PanelStyle.rowHover : .clear)
            layer?.borderWidth = 1
            layer?.borderColor = PanelStyle.resolvedCG(WidgetMarketTone.lineStrong)
        }
        setAccessibilityLabel(titleView.string)
    }
}
