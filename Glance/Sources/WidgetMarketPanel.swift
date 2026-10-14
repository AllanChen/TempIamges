import AppKit

/// Widget Market, built from the Figma "Widget Market Redesign" board (448 × 824):
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
    private let scrollIndicator = WidgetMarketScrollIndicator()
    private let emptyTile = NSView()
    private let emptyIcon = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyHint = NSTextField(labelWithString: "")
    private let footerEdge = NSView()
    private let footerCountLabel = NSTextField(labelWithString: "")
    private let footerHintLabel = NSTextField(labelWithString: "Scroll for more".localized)
    private let loadingOverlay = NSView()
    private let loadingSpinner: NSProgressIndicator = {
        let indicator = NSProgressIndicator(frame: .zero)
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.isIndeterminate = true
        indicator.isDisplayedWhenStopped = false
        return indicator
    }()

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
        makeKeyAndOrderFront(nil)
        if !hasAttemptedLoad { loadCatalog() }
        else if !isLoading { refreshFromServer(showLoading: false) }
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
        refreshCatalog(resetScroll: true)
        refreshFromServer(showLoading: false)
    }

    private func refreshFromServer(showLoading: Bool) {
        guard !isLoading else { return }
        isLoading = true
        if showLoading { setLoading(true) }
        WidgetCatalogClient.shared.fetchAll { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            if showLoading { self.setLoading(false) }
            switch result {
            case .success(let remoteManifests):
                Logger.info("WidgetMarketPanel: refreshed \(remoteManifests.count) widgets from server")
                self.catalogIDs = Set(remoteManifests.map(\.id))
                self.manifests = Self.mergeInstalled(into: remoteManifests)
                self.refreshCatalog(resetScroll: true)
            case .failure(let error):
                Logger.info("WidgetMarketPanel: catalog fetch failed: \(error.localizedDescription)")
            }
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
        loadingOverlay.layer?.backgroundColor = PanelStyle.resolvedCG(HistoryStyle.background.withAlphaComponent(0.94))
        loadingOverlay.addSubview(loadingSpinner)
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
        scrollIndicator.frame = NSRect(x: width - 12, y: Self.listTop + 8, width: 3, height: max(0, scrollView.frame.height - 16))

        emptyTile.frame = NSRect(x: (width - 72) / 2, y: 300, width: 72, height: 72)
        emptyIcon.frame = NSRect(x: 22, y: 22, width: 28, height: 28)
        emptyTitle.frame = NSRect(x: 0, y: 392, width: width, height: 20)
        emptyHint.frame = NSRect(x: 40, y: 420, width: width - 80, height: 16)

        footerEdge.frame = NSRect(x: 0, y: listBottom, width: width, height: 1)
        footerCountLabel.frame = NSRect(x: m, y: listBottom + 8, width: 230, height: 14)
        footerHintLabel.frame = NSRect(x: width - m - 126, y: listBottom + 8, width: 126, height: 14)
        loadingOverlay.frame = bounds
        let spinnerSize: CGFloat = 20
        loadingSpinner.frame = NSRect(x: (width - spinnerSize) / 2,
            y: (height - spinnerSize) / 2, width: spinnerSize, height: spinnerSize)
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
            row.onRemove = { WidgetRegistry.shared.uninstall(id: manifest.id) }
            catalogContainer.addSubview(row)
        }
        subtitleLabel.stringValue = String(format: "%d available  ·  %d installed  ·  %d updates".localized,
                                           catalogIDs.count, installedIDs.count, updates.count)
        footerCountLabel.stringValue = String(format: "%d widgets  •  %@".localized, visible.count, filterTitle)
        searchBox.placeholder = String(format: "Search %d widgets".localized, catalogIDs.count)
        pills.counts = [catalogIDs.count, installedIDs.count, updates.count]
        pills.selectedSegment = catalogFilter.rawValue
        let none = visible.isEmpty
        scrollView.isHidden = none
        [emptyTile, emptyTitle, emptyHint].forEach { $0.isHidden = !none }
        if none {
            let searching = !searchBox.query.isEmpty
            emptyTitle.stringValue = searching ? "No matching widgets".localized : "No widgets available".localized
            emptyHint.stringValue = searching ? "Try a different search, or clear it to see every widget.".localized
                                              : "Refresh to load the catalog.".localized
        }
        if resetScroll { scrollView.contentView.scroll(to: .zero) }
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateScrollIndicator()
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
        scrollIndicator.update(contentHeight: catalogContainer.frame.height,
            viewportHeight: scrollView.contentView.bounds.height, offset: scrollView.contentView.bounds.minY)
        footerHintLabel.isHidden = !scrollable || scrollView.isHidden
    }

    private func setLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
        if loading { loadingSpinner.startAnimation(nil) }
        else { loadingSpinner.stopAnimation(nil) }
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

private final class WidgetMarketScrollIndicator: NSView {
    private let thumb = NSView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine.withAlphaComponent(0.72))
        layer?.cornerRadius = 1.5
        thumb.wantsLayer = true
        thumb.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accent.withAlphaComponent(0.9))
        thumb.layer?.cornerRadius = 1.5
        addSubview(thumb)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(contentHeight: CGFloat, viewportHeight: CGFloat, offset: CGFloat) {
        guard bounds.height > 0, contentHeight > viewportHeight, viewportHeight > 0 else {
            isHidden = true; return
        }
        isHidden = false
        let thumbHeight = max(34, bounds.height * viewportHeight / contentHeight)
        let progress = min(1, max(0, offset / max(1, contentHeight - viewportHeight)))
        thumb.frame = NSRect(x: 0, y: progress * (bounds.height - thumbHeight), width: bounds.width, height: thumbHeight)
    }
}

// MARK: - Catalog row

/// Board row (400 × 84, radius 9): icon tile 48 at (12, 18) with a monogram or
/// the widget icon; name 13 semibold at (72, 14); one-line summary 11 at (72, 36);
/// meta 10 at (72, 58) with the official dot; one action at the right edge, 12 pt
/// inset, 32 pt tall. Hovering an installed row swaps "Installed" for "Remove".
private final class WidgetMarketRowView: NSView {
    var onInstall: (() -> Void)?
    var onRemove: (() -> Void)?
    private let manifest: WidgetManifest
    private let isInstalled: Bool
    private let hasUpdate: Bool
    private let isRemovedFromCatalog: Bool
    private let iconTile = WidgetMarketIconTile()
    private let nameLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let officialDot = NSView()
    private let metaLabel = NSTextField(labelWithString: "")
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
        officialDot.wantsLayer = true
        officialDot.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.success)
        officialDot.layer?.cornerRadius = 3.5
        officialDot.isHidden = !manifest.official
        let count = manifest.commands.count
        let commands = String(format: (count == 1 ? "%d command" : "%d commands").localized, count)
        metaLabel.font = PanelStyle.inspectFont(ofSize: 10)
        metaLabel.textColor = PanelStyle.textTertiary
        metaLabel.stringValue = "\(manifest.author) · v\(manifest.version) · \(commands)"
        for label in [nameLabel, summaryLabel, metaLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }
        addSubview(officialDot)
        action.target = self
        action.action = #selector(actionTapped)
        addSubview(action)
        updateAction()
    }

    /// The one action this row offers right now.
    private var actionStyle: WidgetMarketActionButton.Style {
        if isRemovedFromCatalog { return .remove }
        if hasUpdate { return .update }
        if isInstalled { return hovering ? .remove : .installed }
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
        nameLabel.frame = NSRect(x: 72, y: 14, width: textWidth, height: 16)
        summaryLabel.frame = NSRect(x: 72, y: 36, width: textWidth, height: 14)
        officialDot.frame = NSRect(x: 72, y: 61, width: 7, height: 7)
        let metaX: CGFloat = manifest.official ? 84 : 72
        metaLabel.frame = NSRect(x: metaX, y: 58, width: max(0, textWidth - (metaX - 72)), height: 12)
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
        return action.frame.contains(local) ? action : nil
    }

    private func applyAppearance() {
        // Board: surface #17181D with the line stroke; hover #1C1D22 with a white 14 % stroke.
        layer?.backgroundColor = PanelStyle.resolvedCG(hovering ? HistoryStyle.hex(0x1C1D22) : PanelStyle.inspectChrome)
        layer?.borderColor = hovering ? NSColor.white.withAlphaComponent(0.14).cgColor : PanelStyle.resolvedCG(PanelStyle.inspectLine)
    }

    @objc private func actionTapped() {
        switch action.style {
        case .install, .update: onInstall?()
        case .remove: onRemove?()
        case .installed: break
        }
    }

    /// Two Latin letters from the English name (first letters of the first two
    /// words); a non-Latin name falls back to its first character.
    private static func monogram(for manifest: WidgetManifest) -> String {
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
    private static func tint(for manifest: WidgetManifest) -> NSColor {
        let palette: [Int] = [0x2F2A3A, 0x22312D, 0x342522, 0x202C38, 0x32273A, 0x303022, 0x26313A, 0x2E2A22, 0x223034]
        let index = abs(manifest.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }) % palette.count
        return HistoryStyle.hex(palette[index])
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
