import AppKit

/// Widget Market, built from "Widget Market / Details + Loading" (262:744):
/// bare window controls with a title and subtitle, a search field, filter pills,
/// card rows that say one thing per line and carry exactly one action, and a
/// footer that names the list. Shares its controls with the Task Center.
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
    private static let designSize = NSSize(width: 448, height: 824)
    private static let margin: CGFloat = 24
    private static let rowWidth: CGFloat = 400
    private static let rowHeight: CGFloat = 84
    private static let rowGap: CGFloat = 8
    private static let listTop: CGFloat = 166
    private static let footerHeight: CGFloat = 30

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
    private var catalogFilter: CatalogFilter = .marketplace
    private var sortsByName = false

    private let rootView = WidgetMarketRootView()
    private let dragRegion = WidgetMarketDragRegion()
    private let closeTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1))
    private let minimizeTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1))
    private let zoomTrafficButton = TrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1))
    private let titleLabel = WidgetMarketPassthroughLabel(labelWithString: "Widget Market".localized)
    private let subtitleLabel = WidgetMarketPassthroughLabel(labelWithString: "")
    private lazy var refreshButton = TaskGhostButton(icon: "TaskIconRefresh", tooltip: "Refresh".localized, tint: PanelStyle.textPrimary) { [weak self] in self?.refreshTapped() }
    private lazy var closeButton = TaskGhostButton(icon: "HistoryClose", tooltip: "Close".localized, tint: PanelStyle.textPrimary) { [weak self] in self?.close() }
    private let headerEdge = NSView()
    private let searchBox = TaskSearchBox()
    private let pills = TaskPillBar(titles: ["Marketplace".localized, "Installed".localized, "Updates".localized])
    private lazy var sortButton = TaskGhostButton(icon: "MarketIconSort", tooltip: "Sort by name".localized, tint: PanelStyle.textSecondary) { [weak self] in self?.sortTapped() }
    private let scrollView = NSScrollView()
    private let catalogContainer = WidgetMarketListDocumentView()
    private let scrollIndicator = GlanceScrollIndicator(axis: .vertical)
    private let emptyTile = NSView()
    private let emptyIcon = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyHint = NSTextField(labelWithString: "")
    private let footerEdge = NSView()
    private let footerCountLabel = NSTextField(labelWithString: "")
    private let footerHintLabel = NSTextField(labelWithString: "Scroll for more".localized)
    private let loadingOverlay = WidgetMarketListDocumentView()
    private let loadingLabel = WidgetMarketTextView(labelWithString: "Loading…".localized)
    private let loadingSpinner = WidgetMarketLoadingIndicator()

    private init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.designSize),
                   styleMask: [.borderless, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 400, height: 600)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
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
    }

    override func close() {
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
            case .success(let remoteManifests):
                Logger.info("WidgetMarketPanel: refreshed \(remoteManifests.count) widgets from server")
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
        merged.append(contentsOf: WidgetRegistry.shared.installed.filter { !known.contains($0.id) })
        return merged
    }

    private func refreshInstalledState() {
        installedIDs = Set(WidgetRegistry.shared.installed.map(\.id))
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
                local.taskCreditCost != remote.taskCreditCost ||
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
        rootView.layer?.backgroundColor = PanelStyle.resolvedCG(HistoryStyle.background)
        rootView.layer?.cornerRadius = 16
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.borderWidth = 1
        rootView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        rootView.layer?.masksToBounds = true
        rootView.onLayout = { [weak self] bounds in self?.layoutContent(in: bounds) }

        // Board: "System / Transparent Drag Region" 0,0 × 448,44; bare controls at (20,16).
        rootView.addSubview(dragRegion)
        [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].forEach { rootView.addSubview($0) }
        closeTrafficButton.target = self; closeTrafficButton.action = #selector(closeTapped)
        minimizeTrafficButton.target = self; minimizeTrafficButton.action = #selector(minimizeTapped)
        zoomTrafficButton.target = self; zoomTrafficButton.action = #selector(zoomTapped)
        configure(titleLabel, size: 13, weight: .semibold, color: PanelStyle.textPrimary, alignment: .center)
        configure(subtitleLabel, size: 11, weight: .regular, color: PanelStyle.textTertiary, alignment: .center)
        rootView.addSubview(titleLabel)
        rootView.addSubview(subtitleLabel)
        rootView.addSubview(refreshButton)
        rootView.addSubview(closeButton)
        headerEdge.wantsLayer = true
        headerEdge.layer?.backgroundColor = HistoryStyle.hairline.cgColor
        rootView.addSubview(headerEdge)

        searchBox.onChange = { [weak self] in self?.refreshCatalog(resetScroll: true) }
        rootView.addSubview(searchBox)
        pills.onSelect = { [weak self] index in self?.filterTapped(index) }
        rootView.addSubview(pills)
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

        // Board 04: empty search — a 72 pt tile with the search glyph, a title and a hint.
        emptyTile.wantsLayer = true
        emptyTile.layer?.backgroundColor = PanelStyle.resolvedCG(HistoryStyle.field)
        emptyTile.layer?.cornerRadius = 22
        emptyTile.layer?.borderWidth = 1
        emptyTile.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        emptyIcon.image = HistoryStyle.icon("HistorySearch", color: PanelStyle.textTertiary, size: 28)
        emptyIcon.imageScaling = .scaleProportionallyUpOrDown
        emptyTile.addSubview(emptyIcon)
        rootView.addSubview(emptyTile)
        configure(emptyTitle, size: 16, weight: .semibold, color: PanelStyle.textPrimary, alignment: .center)
        configure(emptyHint, size: 12, weight: .regular, color: PanelStyle.textTertiary, alignment: .center)
        rootView.addSubview(emptyTitle)
        rootView.addSubview(emptyHint)

        footerEdge.wantsLayer = true
        footerEdge.layer?.backgroundColor = HistoryStyle.hairline.cgColor
        rootView.addSubview(footerEdge)
        configure(footerCountLabel, size: 11, weight: .regular, color: PanelStyle.textTertiary, alignment: .left)
        configure(footerHintLabel, size: 11, weight: .regular, color: PanelStyle.textTertiary, alignment: .right)
        rootView.addSubview(footerCountLabel)
        rootView.addSubview(footerHintLabel)

        loadingOverlay.wantsLayer = true
        loadingOverlay.layer?.backgroundColor = PanelStyle.resolvedCG(HistoryStyle.background)
        loadingOverlay.addSubview(loadingSpinner)
        loadingLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        loadingLabel.textColor = PanelStyle.textSecondary
        loadingLabel.alignment = .center
        loadingOverlay.addSubview(loadingLabel)
        rootView.addSubview(loadingOverlay)
        setLoading(false)
        layoutContent(in: rootView.bounds)
    }

    private func configure(_ label: NSTextField, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment) {
        label.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
    }

    /// Board coordinates are top-origin on a 448-wide panel; the root is flipped,
    /// so frames are written as drawn. Width scales with the window, the header
    /// stays anchored at the top and the footer at the bottom.
    private func layoutContent(in bounds: NSRect) {
        let width = bounds.width, height = bounds.height
        let m = Self.margin
        let rowWidth = width - 2 * m
        dragRegion.frame = NSRect(x: 0, y: 0, width: width, height: 44)
        [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].enumerated().forEach { index, button in
            button.frame = NSRect(x: 20 + CGFloat(index) * 26, y: 18, width: 12, height: 12)
        }
        titleLabel.frame = NSRect(x: 0, y: 12, width: width, height: 16)
        subtitleLabel.frame = NSRect(x: 0, y: 31, width: width, height: 13)
        refreshButton.frame = NSRect(x: width - m - 32 * 2 - 8, y: 10, width: 32, height: 32)
        closeButton.frame = NSRect(x: width - m - 32, y: 10, width: 32, height: 32)
        headerEdge.frame = NSRect(x: 0, y: 52, width: width, height: 1)
        searchBox.frame = NSRect(x: m, y: 68, width: rowWidth, height: 36)
        pills.frame = NSRect(x: m, y: 118, width: rowWidth - 40, height: 30)
        sortButton.frame = NSRect(x: width - m - 32, y: 117, width: 32, height: 32)

        let listBottom = height - Self.footerHeight
        scrollView.frame = NSRect(x: m, y: Self.listTop, width: rowWidth, height: max(0, listBottom - Self.listTop))
        catalogContainer.frame.size.width = rowWidth
        for row in catalogContainer.subviews { row.frame.size.width = rowWidth }
        scrollIndicator.frame = NSRect(x: width - 17, y: Self.listTop + 8, width: 12,
                                       height: max(0, scrollView.frame.height - 16))

        emptyTile.frame = NSRect(x: (width - 72) / 2, y: 300, width: 72, height: 72)
        emptyIcon.frame = NSRect(x: 22, y: 22, width: 28, height: 28)
        emptyTitle.frame = NSRect(x: 0, y: 392, width: width, height: 20)
        emptyHint.frame = NSRect(x: 40, y: 420, width: width - 80, height: 16)

        footerEdge.frame = NSRect(x: 0, y: listBottom, width: width, height: 1)
        footerCountLabel.frame = NSRect(x: m, y: listBottom + 8, width: 230, height: 14)
        footerHintLabel.frame = NSRect(x: width - m - 126, y: listBottom + 8, width: 126, height: 14)
        detailView?.frame = NSRect(x: 0, y: 52, width: width, height: max(0, height - 52))
        loadingOverlay.frame = NSRect(x: 0, y: Self.listTop, width: width, height: max(0, listBottom - Self.listTop))
        let spinnerSize: CGFloat = 20
        loadingSpinner.frame = NSRect(x: (width - spinnerSize) / 2,
            y: loadingOverlay.bounds.height / 2 - 28, width: spinnerSize, height: spinnerSize)
        loadingLabel.frame = NSRect(x: 0, y: loadingOverlay.bounds.height / 2 + 8, width: width, height: 16)
        updateScrollIndicator()
    }

    private func refreshCatalog(resetScroll: Bool) {
        catalogContainer.subviews.forEach { $0.removeFromSuperview() }
        let visible = visibleManifests
        let updates = updatesAvailable
        let pitch = Self.rowHeight + Self.rowGap
        let contentHeight = visible.isEmpty ? 0 : CGFloat(visible.count) * pitch - Self.rowGap
        let rowWidth = max(0, scrollView.frame.width)
        catalogContainer.frame = NSRect(x: 0, y: 0, width: rowWidth, height: max(scrollView.contentSize.height, contentHeight))
        for (index, manifest) in visible.enumerated() {
            let row = WidgetMarketRowView(manifest: manifest,
                isInstalled: installedIDs.contains(manifest.id), hasUpdate: updates.contains(manifest.id),
                isRemovedFromCatalog: !catalogIDs.contains(manifest.id))
            row.frame = NSRect(x: 0, y: CGFloat(index) * pitch, width: rowWidth, height: Self.rowHeight)
            row.onInstall = { [weak self] in self?.install(manifest) }
            row.onShowDetails = { [weak self] in self?.showDetails(manifest) }
            catalogContainer.addSubview(row)
        }
        subtitleLabel.stringValue = isLoading && catalogIDs.isEmpty ? "Loading…".localized : String(format: "%d available  ·  %d installed  ·  %d updates".localized,
                                           catalogIDs.count, installedIDs.count, updates.count)
        footerCountLabel.stringValue = isLoading ? "Loading…".localized : String(format: "%d widgets  •  %@".localized, visible.count, filterTitle)
        searchBox.placeholder = isLoading && catalogIDs.isEmpty ? "Search widgets".localized : String(format: "Search %d widgets".localized, catalogIDs.count)
        pills.showsCounts = !isLoading || !catalogIDs.isEmpty
        pills.counts = [catalogIDs.count, installedIDs.count, updates.count]
        pills.selectedSegment = catalogFilter.rawValue
        let none = visible.isEmpty
        scrollView.isHidden = none
        let showEmpty = none && !isLoading && hasFinishedLoad
        [emptyTile, emptyTitle, emptyHint].forEach { $0.isHidden = !showEmpty }
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

    private var filterTitle: String {
        switch catalogFilter {
        case .marketplace: return "Marketplace".localized
        case .installed: return "Installed".localized
        case .updates: return "Updates".localized
        }
    }

    private func updateScrollIndicator() {
        let scrollable = catalogContainer.frame.height > scrollView.contentView.bounds.height + 1
        scrollIndicator.update(contentLength: catalogContainer.frame.height,
            viewportLength: scrollView.contentView.bounds.height, offset: scrollView.contentView.bounds.minY)
        scrollIndicator.isHidden = scrollView.isHidden || !scrollable
        footerHintLabel.isHidden = !scrollable || scrollView.isHidden
    }

    private func setLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
        loadingSpinner.setAnimating(loading)
    }

    private func showDetails(_ manifest: WidgetManifest) {
        selectedWidgetID = manifest.id
        refreshDetail()
    }

    private func refreshDetail() {
        guard let selectedWidgetID else { return }
        guard let manifest = manifests.first(where: { $0.id == selectedWidgetID }) else {
            self.selectedWidgetID = nil
            detailView?.removeFromSuperview()
            detailView = nil
            setCatalogControlsHidden(false)
            return
        }
        let previousOffset = detailView?.scrollOffset
        detailView?.removeFromSuperview()
        let detail = WidgetMarketDetailView(manifest: manifest,
            isInstalled: installedIDs.contains(manifest.id), hasUpdate: updatesAvailable.contains(manifest.id),
            isAvailable: catalogIDs.contains(manifest.id))
        detail.onBack = { [weak self] in
            self?.selectedWidgetID = nil
            self?.detailView?.removeFromSuperview()
            self?.detailView = nil
            self?.setCatalogControlsHidden(false)
            self?.refreshCatalog(resetScroll: false)
        }
        detail.onInstall = { [weak self] in self?.install(manifest) }
        detail.onRemove = { WidgetRegistry.shared.uninstall(id: manifest.id) }
        detailView = detail
        rootView.addSubview(detail, positioned: .above, relativeTo: loadingOverlay)
        setCatalogControlsHidden(true)
        subtitleLabel.stringValue = "Widget details".localized
        layoutContent(in: rootView.bounds)
        detail.layoutSubtreeIfNeeded()
        if let previousOffset { detail.restoreScrollOffset(previousOffset) }
    }

    private func setCatalogControlsHidden(_ hidden: Bool) {
        let controls: [NSView] = [searchBox, pills, sortButton]
        controls.forEach { $0.isHidden = hidden }
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

/// Flipped so the board's top-origin coordinates can be used as written.
private final class WidgetMarketRootView: NSView {
    var onLayout: ((NSRect) -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?(bounds) }
}

/// Board "System / Transparent Drag Region": moves the panel, double-click zooms.
private final class WidgetMarketDragRegion: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) }
        else { window?.performDrag(with: event) }
    }
}

/// Title text that never intercepts the mouse, so the drag region beneath it works.
private final class WidgetMarketPassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
    var maximumTextHeight: CGFloat?
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
        return NSAttributedString(string: stringValue,
            attributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph])
    }

    func fittingTextHeight(width: CGFloat) -> CGFloat {
        ceil(attributedText.boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if let maximumTextHeight {
            size.height = min(maximumTextHeight, fittingTextHeight(width: size.width))
        }
        super.setFrameSize(size)
    }

    override func draw(_ dirtyRect: NSRect) {
        var rect = bounds
        if maximumNumberOfLines > 0 {
            let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
            rect.size.height = min(rect.height, lineHeight * CGFloat(maximumNumberOfLines))
        }
        attributedText.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
    }
}

/// Uses the exact 16 pt Figma chevron, including its 180° rotation.
private final class WidgetMarketBackButton: NSControl {
    private let arrow = CALayer()
    private let label = WidgetMarketTextView(labelWithString: "Back to widgets".localized)
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let image = HistoryStyle.icon("MarketIconBack", color: PanelStyle.textSecondary, size: 16)
        arrow.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        arrow.contentsGravity = .resizeAspect
        layer?.addSublayer(arrow)
        label.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        label.textColor = PanelStyle.textSecondary
        addSubview(label)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Back to widgets".localized)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arrow.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        arrow.position = CGPoint(x: 8, y: 16)
        arrow.transform = CATransform3DMakeRotation(.pi, 0, 0, 1)
        CATransaction.commit()
        label.frame = NSRect(x: 24, y: 8, width: max(0, bounds.width - 40), height: 15)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { if isEnabled { sendAction(action, to: target) } }
    override func keyDown(with event: NSEvent) {
        if isEnabled && (event.keyCode == 36 || event.keyCode == 49) { sendAction(action, to: target) }
        else { super.keyDown(with: event) }
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

/// Board row (400 × 84, radius 9): icon tile 48 at (12, 18) with a monogram or
/// the widget icon; name 13 semibold at (72, 22); two-line summary 11 at (72, 44);
/// one action at the right edge, 12 pt
/// inset, 32 pt tall. Installed rows keep their status on hover; click for details.
private final class WidgetMarketRowView: NSView {
    var onInstall: (() -> Void)?
    var onShowDetails: (() -> Void)?
    private let manifest: WidgetManifest
    private let isInstalled: Bool
    private let hasUpdate: Bool
    private let isRemovedFromCatalog: Bool
    private let iconTile = WidgetMarketIconTile()
    private let nameLabel = WidgetMarketTextView(labelWithString: "")
    private let summaryLabel = WidgetMarketTextView(labelWithString: "")
    private let action = WidgetMarketActionButton()
    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false
    override var isFlipped: Bool { true }

    init(manifest: WidgetManifest, isInstalled: Bool, hasUpdate: Bool, isRemovedFromCatalog: Bool) {
        self.manifest = manifest
        self.isInstalled = isInstalled
        self.hasUpdate = hasUpdate
        self.isRemovedFromCatalog = isRemovedFromCatalog
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(manifest.displayName)
        buildUI()
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        iconTile.configure(monogram: Self.monogram(for: manifest), tint: Self.tint(for: manifest), iconURL: manifest.iconURL)
        addSubview(iconTile)
        nameLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = PanelStyle.textPrimary
        nameLabel.stringValue = manifest.displayName
        summaryLabel.font = PanelStyle.inspectFont(ofSize: 11)
        summaryLabel.textColor = PanelStyle.textSecondary
        summaryLabel.stringValue = manifest.displaySummary
        for label in [nameLabel, summaryLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }
        summaryLabel.maximumNumberOfLines = 2
        summaryLabel.lineBreakMode = .byWordWrapping
        nameLabel.toolTip = manifest.displayName
        summaryLabel.toolTip = manifest.displaySummary
        action.target = self
        action.action = #selector(actionTapped)
        addSubview(action)
        updateAction()
    }

    /// The one action this row offers right now.
    private var actionStyle: WidgetMarketActionButton.Style {
        if isRemovedFromCatalog { return .installed }
        if hasUpdate { return .update }
        if isInstalled { return .installed }
        return .install
    }

    private func updateAction() {
        action.style = actionStyle
        needsLayout = true
    }

    override func layout() {
        super.layout()
        iconTile.frame = NSRect(x: 12, y: 18, width: 48, height: 48)
        let actionWidth = action.style.width
        let actionX = bounds.width - 12 - actionWidth
        action.frame = NSRect(x: actionX, y: 26, width: actionWidth, height: 32)
        let textWidth = max(0, actionX - 72 - 12)
        nameLabel.frame = NSRect(x: 72, y: 22, width: textWidth, height: 16)
        summaryLabel.frame = NSRect(x: 72, y: 44, width: textWidth, height: 26)
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
        return action.frame.contains(local) ? action : self
    }
    override func mouseDown(with event: NSEvent) { onShowDetails?() }

    private func applyAppearance() {
        // Board: surface #17181D with the line stroke; hover #1C1D22 with a white 14 % stroke.
        layer?.backgroundColor = PanelStyle.resolvedCG(hovering ? HistoryStyle.hex(0x1C1D22) : PanelStyle.inspectChrome)
        layer?.borderColor = hovering ? NSColor.white.withAlphaComponent(0.14).cgColor : PanelStyle.resolvedCG(PanelStyle.inspectLine)
    }

    @objc private func actionTapped() {
        switch action.style {
        case .install, .update: onInstall?()
        case .remove, .installed: onShowDetails?()
        }
    }

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

    /// Board tile tints, chosen by the widget id so a widget keeps its colour.
    fileprivate static func tint(for manifest: WidgetManifest) -> NSColor {
        let palette: [Int] = [0x2F2A3A, 0x22312D, 0x342522, 0x202C38, 0x32273A, 0x303022, 0x26313A, 0x2E2A22, 0x223034]
        let index = abs(manifest.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }) % palette.count
        return HistoryStyle.hex(palette[index])
    }
}

/// The second page of the market. Its content scrolls independently while Back
/// and the install/update/remove actions remain available at smaller sizes.
private final class WidgetMarketDetailView: NSView {
    var onBack: (() -> Void)?
    var onInstall: (() -> Void)?
    var onRemove: (() -> Void)?
    private let backButton = WidgetMarketBackButton()
    private let scrollView = NSScrollView()
    private let document = WidgetMarketListDocumentView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    private let actionEdge = NSView()
    private let primaryAction = WidgetMarketActionButton()
    private let removeAction = WidgetMarketActionButton()
    private let isInstalled: Bool
    private let hasUpdate: Bool
    private let isAvailable: Bool
    private var contentHeight: CGFloat = 0
    var scrollOffset: NSPoint { scrollView.contentView.bounds.origin }
    override var isFlipped: Bool { true }

    init(manifest: WidgetManifest, isInstalled: Bool, hasUpdate: Bool, isAvailable: Bool) {
        self.isInstalled = isInstalled
        self.hasUpdate = hasUpdate
        self.isAvailable = isAvailable
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(HistoryStyle.background)
        backButton.target = self
        backButton.action = #selector(goBack)
        addSubview(backButton)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        PanelStyle.styleScrollers(in: scrollView)
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = document
        addSubview(scrollView)
        buildContent(manifest)
        actionEdge.wantsLayer = true
        actionEdge.layer?.backgroundColor = HistoryStyle.hairline.cgColor
        addSubview(actionEdge)
        primaryAction.style = hasUpdate ? .update : .install
        primaryAction.target = self
        primaryAction.action = #selector(installTapped)
        primaryAction.isHidden = !isAvailable || (isInstalled && !hasUpdate)
        addSubview(primaryAction)
        removeAction.style = .remove
        removeAction.target = self
        removeAction.action = #selector(removeTapped)
        removeAction.isHidden = !isInstalled
        addSubview(removeAction)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    private func label(_ value: String, in parent: NSView, x: CGFloat = 0, y: CGFloat,
                       width: CGFloat = 400, height: CGFloat? = nil, size: CGFloat = 13,
                       weight: NSFont.Weight = .regular, color: NSColor = PanelStyle.textSecondary,
                       multiline: Bool = false) -> WidgetMarketTextView {
        let view = WidgetMarketTextView(labelWithString: value)
        view.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        view.textColor = color
        let lineHeight: CGFloat = size <= 11 ? 13 : size <= 12 ? 15 : 16
        view.frame = NSRect(x: x, y: y, width: width, height: height ?? lineHeight)
        view.autoresizingMask = [.width]
        view.maximumNumberOfLines = multiline ? 0 : 1
        view.lineBreakMode = multiline ? .byWordWrapping : .byTruncatingTail
        if multiline {
            view.maximumTextHeight = height ?? lineHeight
            view.setFrameSize(NSSize(width: width, height: height ?? lineHeight))
        }
        view.toolTip = value
        parent.addSubview(view)
        return view
    }

    private func card(y: CGFloat, height: CGFloat) -> NSView {
        let view = WidgetMarketListDocumentView(frame: NSRect(x: 0, y: y, width: 400, height: height))
        view.autoresizingMask = [.width]
        view.wantsLayer = true
        view.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = 1
        view.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        document.addSubview(view)
        return view
    }

    private func buildContent(_ manifest: WidgetManifest) {
        let icon = WidgetMarketIconTile(frame: NSRect(x: 0, y: 8, width: 64, height: 64))
        icon.configure(monogram: WidgetMarketRowView.monogram(for: manifest),
                       tint: WidgetMarketRowView.tint(for: manifest), iconURL: manifest.iconURL)
        document.addSubview(icon)
        label(manifest.displayName, in: document, x: 84, y: 8, width: 316, height: 22,
              size: 18, weight: .semibold, color: PanelStyle.textPrimary)
        label((isInstalled ? "Installed" : "Not installed").localized, in: document,
              x: 84, y: 40, width: 316, size: 11, color: isInstalled ? PanelStyle.success : PanelStyle.textTertiary)
        label(manifest.displaySummary, in: document, y: 98, height: 48, multiline: true)
        let price = card(y: 162, height: 64)
        label("Cost per task".localized, in: price, x: 16, y: 23, width: 180, size: 12)
        let value = label(manifest.taskCreditCost == 0 ? "Free of charge".localized : manifest.creditCostLabel,
                          in: price, x: 196, y: 22, width: 188, height: 16, size: 13,
                          weight: .semibold, color: PanelStyle.textPrimary)
        value.alignment = .right
        label("Commands".localized, in: document, y: 254, size: 12,
              weight: .semibold, color: PanelStyle.textPrimary)
        var y: CGFloat = 278
        for command in manifest.localizedCommands {
            let tile = card(y: y, height: 96)
            label(command.name, in: tile, x: 16, y: 14, width: 368, size: 13,
                  weight: .semibold, color: PanelStyle.textPrimary)
            label(command.description, in: tile, x: 16, y: 40, width: 368, height: 42,
                  size: 12, multiline: true)
            y += 108
        }
        let inputs = Set(manifest.commands.flatMap(\.inputTypes)).sorted().map { $0.capitalized.localized }.joined(separator: ", ")
        let outputs = Set(manifest.commands.flatMap(\.outputs)).sorted().map { $0.capitalized.localized }.joined(separator: ", ")
        label("\("Input".localized): \(inputs)", in: document, y: y + 6, size: 12)
        label("\("Output".localized): \(outputs)", in: document, y: y + 30, size: 12)
        label("Privacy".localized, in: document, y: y + 80, size: 12,
              weight: .semibold, color: PanelStyle.textPrimary)
        label(manifest.privacy.notice, in: document, y: y + 106, height: 72, size: 12, multiline: true)
        contentHeight = y + 196
    }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 48)
        backButton.frame = NSRect(x: 24, y: 16, width: width, height: 32)
        scrollView.frame = NSRect(x: 24, y: 58, width: width, height: max(0, bounds.height - 158))
        document.frame.size = NSSize(width: width, height: max(contentHeight, scrollView.contentSize.height))
        actionEdge.frame = NSRect(x: 24, y: bounds.height - 100, width: width, height: 1)
        let paired = !primaryAction.isHidden && !removeAction.isHidden
        primaryAction.frame = NSRect(x: 24, y: bounds.height - 76, width: paired ? max(0, width - 132) : width, height: 40)
        removeAction.frame = NSRect(x: paired ? bounds.width - 144 : 24, y: bounds.height - 76, width: paired ? 120 : width, height: 40)
    }

    @objc private func goBack() { onBack?() }
    @objc private func installTapped() { onInstall?() }
    @objc private func removeTapped() { onRemove?() }

    func restoreScrollOffset(_ offset: NSPoint) {
        let maxY = max(0, document.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, offset.y), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// 48 pt tile, radius 10: a tinted background with a two-letter monogram, replaced
/// by the widget icon (aspect fill) once it loads.
private final class WidgetMarketIconTile: NSView {
    private static var iconCache: [URL: NSImage] = [:]
    private let monogramLabel = PanelCenteredTextView()
    private let iconLayer = CALayer()
    private var pendingURL: URL?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.masksToBounds = true
        monogramLabel.font = PanelStyle.inspectFont(ofSize: 15, weight: .semibold)
        monogramLabel.textColor = PanelStyle.textSecondary
        addSubview(monogramLabel)
        iconLayer.contentsGravity = .resizeAspectFill
        iconLayer.masksToBounds = true
        iconLayer.isHidden = true
        layer?.addSublayer(iconLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(monogram: String, tint: NSColor, iconURL: URL?) {
        monogramLabel.string = monogram
        layer?.backgroundColor = PanelStyle.resolvedCG(tint)
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

/// The row's single action. Board: 32 pt tall, radius 10, 12 pt semibold label.
/// install / update: accent fill, ink text. installed: green 14 % fill, 45 % stroke.
/// remove: red 8 % fill, 32 % stroke.
private final class WidgetMarketActionButton: NSButton {
    enum Style {
        case install, installed, update, remove
        var width: CGFloat {
            switch self {
            case .install, .update: return 76
            case .installed: return 88
            case .remove: return 84
            }
        }
        var title: String {
            switch self {
            case .install: return "Install".localized
            case .installed: return "Installed".localized
            case .update: return "Update".localized
            case .remove: return "Remove".localized
            }
        }
    }
    var style: Style = .install { didSet { applyAppearance() } }
    private let titleView = PanelCenteredTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 10
        titleView.font = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
        addSubview(titleView)
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() { super.layout(); titleView.frame = bounds }

    private func applyAppearance() {
        titleView.string = style.title
        switch style {
        case .install, .update:
            titleView.textColor = PanelStyle.accentInk
            layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accent)
            layer?.borderWidth = 0
        case .installed:
            titleView.textColor = PanelStyle.success
            layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.success.withAlphaComponent(0.14))
            layer?.borderWidth = 1
            layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.success.withAlphaComponent(0.45))
        case .remove:
            titleView.textColor = PanelStyle.failure
            layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.failure.withAlphaComponent(0.08))
            layer?.borderWidth = 1
            layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.failure.withAlphaComponent(0.32))
        }
        setAccessibilityLabel(titleView.string)
    }
}
