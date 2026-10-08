import AppKit

/// Compact Widget marketplace shown alongside the main Glance window.
/// The panel stays focused on the searchable catalog and install actions.
final class WidgetMarketPanel: NSPanel, NSSearchFieldDelegate {
    static let shared = WidgetMarketPanel()

    private enum CatalogFilter: Int { case marketplace, installed, updates }
    private static let designSize = NSSize(width: 448, height: 824)
    private static let titlebarHeight: CGFloat = 48
    private static let rowHeight: CGFloat = 84

    private weak var attachedParent: NSWindow?
    private var manifests: [WidgetManifest] = []
    private var installedIDs = Set<String>()
    private var isLoading = false
    private var hasAttemptedLoad = false
    private var catalogFilter: CatalogFilter = .marketplace
    private var sortsByName = false

    private static let officialWidgets: [(id: String, name: String, summary: String, commandName: String, commandDescription: String, taskType: String, privacy: String)] = [
        ("a0d3311a-b952-4831-8ee4-69f72c381a88", "Remove Background",
         "Remove an image background while preserving fine subject edges.",
         "Remove Background", "Create a transparent-background copy of the selected image.",
         "image.remove-background.v1", "The selected image will be uploaded to Glance for cloud processing."),
        ("ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f", "超分",
         "图生图超分辨率，提升图片清晰度与细节。", "超分",
         "上传一张图片，生成更高分辨率的清晰版本。", "image.upscale.v1",
         "The selected image will be uploaded to Glance for cloud processing."),
        ("7cc3967a-60ac-4677-9817-72f57f5ef5fa", "RemoveBG 高级",
         "图生图高级背景移除，保留精细主体边缘。", "RemoveBG 高级",
         "上传一张图片，高级移除背景并生成透明背景副本。", "image.remove-bg-pro.v1",
         "The selected image will be uploaded to Glance for cloud processing.")
    ]

    private let rootView = WidgetMarketRootView()
    private let titlebar = WidgetMarketTitlebar()
    private let closeTrafficButton = WidgetMarketTrafficButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1))
    private let minimizeTrafficButton = WidgetMarketTrafficButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1))
    private let zoomTrafficButton = WidgetMarketTrafficButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1))
    private let titleLabel = PanelCenteredTextView()
    private let titlebarDivider = NSView()
    private let refreshButton = WidgetMarketIconButton(symbol: "arrow.clockwise", accessibilityLabel: "Refresh".localized)
    private let closeButton = WidgetMarketIconButton(symbol: "xmark", accessibilityLabel: "Close".localized)

    private let catalogPane = NSView()
    private let catalogHeading = NSTextField(labelWithString: "Widgets".localized)
    private let catalogCount = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let marketplaceFilterButton = WidgetMarketFilterButton(title: "Marketplace".localized)
    private let installedFilterButton = WidgetMarketFilterButton(title: "Installed".localized)
    private let updatesFilterButton = WidgetMarketFilterButton(title: "Updates".localized)
    private let sortButton = WidgetMarketIconButton(symbol: "arrow.up.arrow.down", accessibilityLabel: "Sort Widgets".localized)
    private let listHeaderDivider = NSView()
    private let scrollView = NSScrollView()
    private let catalogContainer = WidgetMarketListDocumentView()
    private let scrollIndicator = WidgetMarketScrollIndicator()
    private let catalogFooter = NSView()
    private let footerCountLabel = NSTextField(labelWithString: "")
    private let footerHintLabel = NSTextField(labelWithString: "Scroll for more".localized)
    private let loadingOverlay = NSView()
    private let loadingSpinner = FocusSweepLoadingView(frame: .zero)

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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func toggle(from parent: NSWindow) {
        if isVisible, attachedParent === parent { close(); return }
        if let attachedParent { attachedParent.removeChildWindow(self) }
        attachedParent = parent
        position(alongside: parent)
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
        if !hasAttemptedLoad { loadCatalog() }
        else if !isLoading { refreshFromServer(showLoading: false) }
    }

    override func close() {
        if let attachedParent { attachedParent.removeChildWindow(self) }
        attachedParent = nil
        orderOut(nil)
    }

    private func loadCatalog() {
        guard !hasAttemptedLoad else { return }
        hasAttemptedLoad = true
        manifests = Self.mergeInstalled(into: Self.makeOfflineManifests())
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

    private static func makeOfflineManifests() -> [WidgetManifest] {
        officialWidgets.map {
            WidgetManifest(schemaVersion: 1, id: $0.id, version: "1.0.0", name: $0.name,
                summary: $0.summary, author: "Glance Labs", iconURL: URL(string: "about:blank")!,
                official: true, execution: WidgetExecution(mode: "cloud"),
                commands: [WidgetCommand(id: $0.id, name: $0.commandName,
                    description: $0.commandDescription, inputTypes: ["image"],
                    inputMimeTypes: ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"],
                    outputs: ["image"], taskType: $0.taskType, requiresUpload: true,
                    parameterSchema: [:])],
                privacy: WidgetPrivacy(uploadsMedia: true, notice: $0.privacy),
                minimumGlanceVersion: "2.0.0", updatedAt: "",
                signature: WidgetSignature(algorithm: "Ed25519", keyID: "", value: ""))
        }
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
            guard let local = WidgetRegistry.shared.installed.first(where: { $0.id == remote.id }) else { continue }
            if local.version != remote.version { result.insert(remote.id) }
        }
        return result
    }

    private var visibleManifests: [WidgetManifest] {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let updates = updatesAvailable
        var result = manifests.filter { manifest in
            switch catalogFilter {
            case .marketplace: break
            case .installed: guard installedIDs.contains(manifest.id) else { return false }
            case .updates: guard updates.contains(manifest.id) else { return false }
            }
            guard !query.isEmpty else { return true }
            let haystack = ([manifest.name, manifest.summary, manifest.author]
                + manifest.commands.flatMap { [$0.name, $0.description] }).joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
        if sortsByName {
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return result
    }

    @objc private func registryDidChange() { refreshInstalledState() }

    private func buildUI() {
        let windowContainer = NSView()
        windowContainer.wantsLayer = true
        windowContainer.layer?.cornerRadius = 16
        windowContainer.layer?.cornerCurve = .continuous
        windowContainer.layer?.masksToBounds = true
        contentView = windowContainer
        windowContainer.superview?.wantsLayer = true
        windowContainer.superview?.layer?.cornerRadius = 16
        windowContainer.superview?.layer?.cornerCurve = .continuous
        windowContainer.superview?.layer?.masksToBounds = true

        let frost = PanelStyle.makeFrostedBase(cornerRadius: 16)
        frost.layer?.borderWidth = 1
        frost.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        frost.frame = windowContainer.bounds
        frost.autoresizingMask = [.width, .height]
        windowContainer.addSubview(frost)
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 16
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.masksToBounds = true
        rootView.frame = frost.bounds
        rootView.autoresizingMask = [.width, .height]
        rootView.onLayout = { [weak self] bounds in self?.layoutContent(in: bounds) }
        frost.addSubview(rootView)

        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        rootView.addSubview(titlebar)
        [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].forEach { titlebar.addSubview($0) }
        closeTrafficButton.target = self; closeTrafficButton.action = #selector(closeTapped)
        minimizeTrafficButton.target = self; minimizeTrafficButton.action = #selector(minimizeTapped)
        zoomTrafficButton.target = self; zoomTrafficButton.action = #selector(zoomTapped)
        titleLabel.string = "Widget Market".localized
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        titlebar.addSubview(titleLabel)
        titlebarDivider.wantsLayer = true
        titlebarDivider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        titlebar.addSubview(titlebarDivider)
        refreshButton.target = self; refreshButton.action = #selector(refreshTapped)
        closeButton.target = self; closeButton.action = #selector(closeTapped)
        titlebar.addSubview(refreshButton); titlebar.addSubview(closeButton)

        catalogPane.wantsLayer = true
        catalogPane.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectCanvas)
        catalogPane.layer?.borderWidth = 1
        catalogPane.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        rootView.addSubview(catalogPane)
        catalogHeading.font = PanelStyle.inspectFont(ofSize: 18, weight: .semibold)
        catalogHeading.textColor = PanelStyle.textPrimary
        catalogPane.addSubview(catalogHeading)
        catalogCount.font = PanelStyle.inspectFont(ofSize: 10, weight: .medium)
        catalogCount.textColor = PanelStyle.textTertiary
        catalogCount.alignment = .right
        catalogPane.addSubview(catalogCount)

        searchField.delegate = self
        searchField.font = PanelStyle.inspectFont(ofSize: 12)
        searchField.textColor = PanelStyle.textPrimary
        searchField.focusRingType = .none
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 8
        searchField.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        searchField.layer?.borderWidth = 1
        searchField.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.accent.withAlphaComponent(0.52))
        catalogPane.addSubview(searchField)

        for (index, button) in [marketplaceFilterButton, installedFilterButton, updatesFilterButton].enumerated() {
            button.tag = index; button.target = self; button.action = #selector(filterTapped(_:))
            catalogPane.addSubview(button)
        }
        sortButton.target = self; sortButton.action = #selector(sortTapped)
        catalogPane.addSubview(sortButton)
        listHeaderDivider.wantsLayer = true
        listHeaderDivider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        catalogPane.addSubview(listHeaderDivider)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = catalogContainer
        scrollView.contentView.postsBoundsChangedNotifications = true
        catalogPane.addSubview(scrollView)
        catalogPane.addSubview(scrollIndicator)
        NotificationCenter.default.addObserver(self, selector: #selector(listBoundsDidChange),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        catalogFooter.wantsLayer = true
        catalogFooter.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        catalogFooter.layer?.borderWidth = 1
        catalogFooter.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        catalogPane.addSubview(catalogFooter)
        footerCountLabel.font = PanelStyle.inspectFont(ofSize: 10)
        footerCountLabel.textColor = PanelStyle.textTertiary
        catalogFooter.addSubview(footerCountLabel)
        footerHintLabel.font = PanelStyle.inspectFont(ofSize: 10)
        footerHintLabel.textColor = PanelStyle.textTertiary
        footerHintLabel.alignment = .right
        catalogFooter.addSubview(footerHintLabel)

        loadingOverlay.wantsLayer = true
        loadingOverlay.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectBackground.withAlphaComponent(0.94))
        loadingSpinner.setLoading(true)
        loadingOverlay.addSubview(loadingSpinner)
        rootView.addSubview(loadingOverlay)
        setLoading(false)
        updateFilterButtons()
        layoutContent(in: rootView.bounds)
    }

    private func layoutContent(in bounds: NSRect) {
        let width = bounds.width, height = bounds.height
        let catalogWidth = width
        let contentHeight = max(0, height - Self.titlebarHeight)
        titlebar.frame = NSRect(x: 0, y: height - Self.titlebarHeight, width: width, height: Self.titlebarHeight)
        closeTrafficButton.frame = NSRect(x: 14, y: 14, width: 20, height: 20)
        minimizeTrafficButton.frame = NSRect(x: 34, y: 14, width: 20, height: 20)
        zoomTrafficButton.frame = NSRect(x: 54, y: 14, width: 20, height: 20)
        titleLabel.frame = NSRect(x: 0, y: 15, width: width, height: 18)
        titlebarDivider.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        refreshButton.frame = NSRect(x: width - 96, y: 5, width: 38, height: 38)
        closeButton.frame = NSRect(x: width - 52, y: 5, width: 38, height: 38)

        catalogPane.frame = NSRect(x: 0, y: 0, width: catalogWidth, height: contentHeight)
        catalogHeading.frame = topFrame(x: 20, y: 17, width: 180, height: 22, in: contentHeight)
        catalogCount.frame = topFrame(x: catalogWidth - 136, y: 22, width: 116, height: 14, in: contentHeight)
        searchField.frame = topFrame(x: 16, y: 53, width: catalogWidth - 32, height: 38, in: contentHeight)
        marketplaceFilterButton.frame = topFrame(x: 16, y: 103, width: 132, height: 30, in: contentHeight)
        installedFilterButton.frame = topFrame(x: 156, y: 103, width: 116, height: 30, in: contentHeight)
        updatesFilterButton.frame = topFrame(x: 280, y: 103, width: 104, height: 30, in: contentHeight)
        sortButton.frame = topFrame(x: catalogWidth - 54, y: 99, width: 38, height: 38, in: contentHeight)
        sortButton.isHidden = catalogWidth < 432
        listHeaderDivider.frame = topFrame(x: 0, y: 145, width: catalogWidth, height: 1, in: contentHeight)
        let listBottom: CGFloat = 30
        let listTop = max(listBottom, contentHeight - 146)
        scrollView.frame = NSRect(x: 0, y: listBottom, width: catalogWidth, height: max(0, listTop - listBottom))
        catalogContainer.frame.size.width = max(0, catalogWidth - 4)
        scrollIndicator.frame = NSRect(x: catalogWidth - 7, y: listBottom + 8,
                                       width: 3, height: max(0, scrollView.frame.height - 16))
        catalogFooter.frame = NSRect(x: 0, y: 0, width: catalogWidth, height: 30)
        footerCountLabel.frame = NSRect(x: 16, y: 8, width: 230, height: 14)
        footerHintLabel.frame = NSRect(x: catalogWidth - 142, y: 8, width: 126, height: 14)
        loadingOverlay.frame = bounds
        loadingSpinner.frame = NSRect(x: (width - FocusSweepLoadingView.preferredSize.width) / 2,
            y: (height - FocusSweepLoadingView.preferredSize.height) / 2,
            width: FocusSweepLoadingView.preferredSize.width, height: FocusSweepLoadingView.preferredSize.height)
        updateScrollIndicator()
    }

    private func topFrame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, in containerHeight: CGFloat) -> NSRect {
        NSRect(x: x, y: containerHeight - y - height, width: width, height: height)
    }

    private func refreshCatalog(resetScroll: Bool) {
        catalogContainer.subviews.forEach { $0.removeFromSuperview() }
        let visible = visibleManifests
        let contentHeight = max(scrollView.contentSize.height, CGFloat(visible.count) * Self.rowHeight)
        catalogContainer.frame = NSRect(x: 0, y: 0, width: max(0, scrollView.contentSize.width - 4), height: contentHeight)
        let updates = updatesAvailable
        for (index, manifest) in visible.enumerated() {
            let row = WidgetMarketRowView(manifest: manifest,
                isInstalled: installedIDs.contains(manifest.id), hasUpdate: updates.contains(manifest.id))
            row.frame = NSRect(x: 0, y: CGFloat(index) * Self.rowHeight,
                               width: catalogContainer.frame.width, height: Self.rowHeight)
            row.onInstall = { [weak self] in self?.install(manifest) }
            catalogContainer.addSubview(row)
        }
        catalogCount.stringValue = String(format: "%d available".localized, manifests.count)
        footerCountLabel.stringValue = String(format: "%d widgets  •  %@".localized, visible.count, filterTitle)
        searchField.placeholderString = String(format: "Search %d widgets".localized, manifests.count)
        marketplaceFilterButton.count = manifests.count
        installedFilterButton.count = installedIDs.count
        updatesFilterButton.count = updates.count
        updateFilterButtons()
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

    private func updateFilterButtons() {
        marketplaceFilterButton.isSelected = catalogFilter == .marketplace
        installedFilterButton.isSelected = catalogFilter == .installed
        updatesFilterButton.isSelected = catalogFilter == .updates
    }

    private func updateScrollIndicator() {
        scrollIndicator.update(contentHeight: catalogContainer.frame.height,
            viewportHeight: scrollView.contentView.bounds.height, offset: scrollView.contentView.bounds.minY)
    }

    private func setLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
        loadingSpinner.setLoading(loading)
    }

    func controlTextDidChange(_ obj: Notification) { refreshCatalog(resetScroll: true) }

    @objc private func filterTapped(_ sender: WidgetMarketFilterButton) {
        guard let filter = CatalogFilter(rawValue: sender.tag), filter != catalogFilter else { return }
        catalogFilter = filter
        refreshCatalog(resetScroll: true)
    }

    @objc private func sortTapped() {
        sortsByName.toggle()
        sortButton.isActive = sortsByName
        refreshCatalog(resetScroll: true)
    }

    @objc private func listBoundsDidChange() { updateScrollIndicator() }
    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }
    @objc private func refreshTapped() { hasAttemptedLoad = true; refreshFromServer(showLoading: true) }

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
        let rightX = parent.frame.maxX + gap
        let leftX = parent.frame.minX - gap - size.width
        let rightSpace = visibleFrame.maxX - rightX
        let leftSpace = leftX - visibleFrame.minX
        let x: CGFloat
        if rightSpace >= size.width {
            x = rightX
        } else if leftSpace >= size.width {
            x = leftX
        } else {
            x = rightSpace >= leftSpace ? visibleFrame.maxX - size.width : visibleFrame.minX
        }
        let frame = NSRect(x: x, y: parent.frame.maxY - size.height, width: size.width, height: size.height)
        setFrame(ScreenManager.shared.clampedToVisible(frame), display: true)
    }
}

// MARK: - Layout and chrome

private final class WidgetMarketRootView: NSView {
    var onLayout: ((NSRect) -> Void)?
    override func layout() { super.layout(); onLayout?(bounds) }
}

private final class WidgetMarketTitlebar: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) }
        else { window?.performDrag(with: event) }
    }
}

private final class WidgetMarketTrafficButton: NSControl {
    private let dot = CALayer()

    init(color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        dot.backgroundColor = PanelStyle.resolvedCG(color)
        dot.cornerRadius = 6
        dot.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        dot.shadowOpacity = 1
        dot.shadowOffset = CGSize(width: 0, height: -1)
        dot.shadowRadius = 1.5
        layer?.addSublayer(dot)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }
    override func layout() {
        super.layout()
        dot.frame = CGRect(x: (bounds.width - 12) / 2, y: (bounds.height - 12) / 2,
                           width: 12, height: 12)
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        sendAction(action, to: target)
    }
}

private final class WidgetMarketIconButton: NSButton {
    private let glyph = NSImageView()
    var isActive = false { didSet { applyAppearance() } }

    init(symbol: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.imageScaling = .scaleProportionallyUpOrDown
        addSubview(glyph)
        setAccessibilityLabel(accessibilityLabel)
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }
    override func layout() {
        super.layout()
        glyph.frame = NSRect(x: (bounds.width - 18) / 2, y: (bounds.height - 18) / 2,
                             width: 18, height: 18)
    }
    private func applyAppearance() {
        layer?.backgroundColor = PanelStyle.resolvedCG(isActive ? PanelStyle.accentSubtleFill : PanelStyle.inspectToolbar)
        layer?.borderColor = PanelStyle.resolvedCG(isActive ? PanelStyle.accent.withAlphaComponent(0.58) : PanelStyle.inspectLine)
        glyph.contentTintColor = isActive ? PanelStyle.accent : PanelStyle.textPrimary
    }
}

private final class WidgetMarketFilterButton: NSButton {
    private let labelView = PanelCenteredTextView()
    private let countView = PanelCenteredTextView()
    var count = 0 { didSet { countView.string = "\(count)" } }
    var isSelected = false { didSet { applyAppearance() } }

    init(title: String) {
        super.init(frame: .zero)
        isBordered = false
        self.title = ""
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        labelView.string = title
        countView.font = PanelStyle.inspectFont(ofSize: 10)
        countView.alignment = .right
        addSubview(labelView)
        addSubview(countView)
        setAccessibilityLabel(title)
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        labelView.frame = NSRect(x: 10, y: 7, width: max(0, bounds.width - 49), height: 16)
        countView.frame = NSRect(x: max(10, bounds.width - 36), y: 7, width: 26, height: 16)
    }
    private func applyAppearance() {
        layer?.backgroundColor = PanelStyle.resolvedCG(isSelected ? PanelStyle.accentSubtleFill : NSColor.clear)
        layer?.borderColor = PanelStyle.resolvedCG(isSelected ? PanelStyle.accent.withAlphaComponent(0.44) : PanelStyle.inspectLine)
        labelView.textColor = isSelected ? PanelStyle.accent : PanelStyle.textSecondary
        labelView.font = PanelStyle.inspectFont(ofSize: 10, weight: isSelected ? .semibold : .medium)
        countView.textColor = PanelStyle.textTertiary
    }
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
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(contentHeight: CGFloat, viewportHeight: CGFloat, offset: CGFloat) {
        guard bounds.height > 0, contentHeight > viewportHeight, viewportHeight > 0 else {
            isHidden = true; return
        }
        isHidden = false
        let thumbHeight = max(34, bounds.height * viewportHeight / contentHeight)
        let progress = min(1, max(0, offset / max(1, contentHeight - viewportHeight)))
        thumb.frame = NSRect(x: 0, y: bounds.height - thumbHeight - progress * (bounds.height - thumbHeight),
                             width: bounds.width, height: thumbHeight)
    }
}

// MARK: - Catalog row

private final class WidgetMarketRowView: NSView {
    var onInstall: (() -> Void)?
    private let manifest: WidgetManifest
    private let isInstalled: Bool
    private let hasUpdate: Bool
    private let divider = NSView()
    private let iconView = WidgetMarketIconView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let verifiedDot = NSView()
    private let publisherLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let updateBadge = WidgetMarketBadgeView(title: "UPDATE", color: PanelStyle.accent)
    private let installButton = WidgetMarketActionButton()
    private let installedBadge = WidgetMarketBadgeView(title: "Installed".localized, color: PanelStyle.success)
    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false

    init(manifest: WidgetManifest, isInstalled: Bool, hasUpdate: Bool) {
        self.manifest = manifest
        self.isInstalled = isInstalled
        self.hasUpdate = hasUpdate
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(manifest.name)
        buildUI()
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        addSubview(divider)
        iconView.letter = Self.initials(for: manifest.name)
        iconView.highlighted = false
        addSubview(iconView)
        nameLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = PanelStyle.textPrimary
        nameLabel.stringValue = manifest.name
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
        verifiedDot.wantsLayer = true
        verifiedDot.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.success)
        verifiedDot.layer?.cornerRadius = 3.5
        verifiedDot.isHidden = !manifest.official
        addSubview(verifiedDot)
        publisherLabel.font = PanelStyle.inspectFont(ofSize: 10)
        publisherLabel.textColor = PanelStyle.textTertiary
        publisherLabel.stringValue = manifest.author
        publisherLabel.lineBreakMode = .byTruncatingTail
        addSubview(publisherLabel)
        summaryLabel.font = PanelStyle.inspectFont(ofSize: 10)
        summaryLabel.textColor = PanelStyle.textSecondary
        summaryLabel.stringValue = manifest.summary
        summaryLabel.lineBreakMode = .byTruncatingTail
        addSubview(summaryLabel)
        metadataLabel.font = PanelStyle.inspectFont(ofSize: 9)
        metadataLabel.textColor = PanelStyle.textTertiary
        metadataLabel.stringValue = "v\(manifest.version)   ·   \(manifest.commands.count) \(manifest.commands.count == 1 ? "command" : "commands")"
        addSubview(metadataLabel)
        updateBadge.isHidden = !hasUpdate
        addSubview(updateBadge)
        if isInstalled && !hasUpdate {
            addSubview(installedBadge)
        } else {
            installButton.style = hasUpdate ? .update : .install
            installButton.target = self
            installButton.action = #selector(installTapped)
            addSubview(installButton)
        }
    }

    override func layout() {
        super.layout()
        divider.frame = NSRect(x: 16, y: 0, width: max(0, bounds.width - 32), height: 1)
        iconView.frame = NSRect(x: 16, y: 22, width: 48, height: 48)
        let showsInstalledBadge = isInstalled && !hasUpdate
        let actionWidth: CGFloat = showsInstalledBadge ? 82 : 68
        let actionX = bounds.width - actionWidth - 18
        nameLabel.frame = NSRect(x: 78, y: 59, width: max(70, actionX - 90), height: 16)
        verifiedDot.frame = NSRect(x: 78, y: 43, width: 7, height: 7)
        publisherLabel.frame = NSRect(x: manifest.official ? 91 : 78, y: 39,
                                      width: max(70, actionX - (manifest.official ? 103 : 90)), height: 13)
        summaryLabel.frame = NSRect(x: 78, y: 22, width: max(80, actionX - 90), height: 13)
        metadataLabel.frame = NSRect(x: 78, y: 6, width: 160, height: 12)
        updateBadge.frame = NSRect(x: min(250, max(170, actionX - 65)), y: 4, width: 54, height: 19)
        if showsInstalledBadge { installedBadge.frame = NSRect(x: actionX, y: 26, width: actionWidth, height: 31) }
        else { installButton.frame = NSRect(x: actionX, y: 26, width: actionWidth, height: 31) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area); trackingAreaRef = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; applyAppearance() }
    override func mouseExited(with event: NSEvent) { hovering = false; applyAppearance() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if (!isInstalled || hasUpdate), installButton.frame.contains(local) { return installButton }
        return nil
    }
    private func applyAppearance() {
        let color: NSColor = hovering ? PanelStyle.inspectToolbar.withAlphaComponent(0.72) : PanelStyle.inspectCanvas
        layer?.backgroundColor = PanelStyle.resolvedCG(color)
    }
    @objc private func installTapped() { onInstall?() }
    private static func initials(for name: String) -> String {
        let words = name.split(separator: " ")
        if words.count > 1 { return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
        return String(name.prefix(2)).uppercased()
    }
}

private final class WidgetMarketIconView: NSView {
    var letter = "W" { didSet { letterLabel.string = letter } }
    var highlighted = false { didSet { applyAppearance() } }
    private let letterLabel = PanelCenteredTextView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 10
        letterLabel.font = PanelStyle.inspectFont(ofSize: 14, weight: .semibold)
        letterLabel.string = letter
        addSubview(letterLabel)
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); letterLabel.frame = bounds }
    private func applyAppearance() {
        layer?.backgroundColor = PanelStyle.resolvedCG(NSColor(srgbRed: 52 / 255, green: 37 / 255, blue: 34 / 255, alpha: 1))
        layer?.borderColor = PanelStyle.resolvedCG(highlighted ? PanelStyle.accent.withAlphaComponent(0.52) : PanelStyle.inspectLine)
        letterLabel.textColor = highlighted ? PanelStyle.accent : PanelStyle.textSecondary
    }
}

private final class WidgetMarketBadgeView: NSView {
    private let label = PanelCenteredTextView()
    init(title: String, color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.backgroundColor = PanelStyle.resolvedCG(color.withAlphaComponent(0.12))
        layer?.borderColor = PanelStyle.resolvedCG(color.withAlphaComponent(0.42))
        label.string = title
        label.font = PanelStyle.inspectFont(ofSize: 9, weight: .semibold)
        label.textColor = color
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); label.frame = bounds }
}

private final class WidgetMarketActionButton: NSButton {
    enum Style { case install, installed, update }
    var style: Style = .install { didSet { applyAppearance() } }
    private let titleView = PanelCenteredTextView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        addSubview(titleView)
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); titleView.frame = bounds }
    private func applyAppearance() {
        titleView.font = PanelStyle.inspectFont(ofSize: 11, weight: .semibold)
        switch style {
        case .install:
            titleView.string = "Install".localized
            titleView.textColor = PanelStyle.accentInk
            layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accent)
            layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.accent.withAlphaComponent(0.5))
        case .installed:
            titleView.string = "Installed".localized
            titleView.textColor = PanelStyle.success
            layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.success.withAlphaComponent(0.12))
            layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.success.withAlphaComponent(0.5))
        case .update:
            titleView.string = "Update".localized
            titleView.textColor = PanelStyle.accentInk
            layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accent)
            layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.accent.withAlphaComponent(0.5))
        }
        setAccessibilityLabel(titleView.string)
    }
}
