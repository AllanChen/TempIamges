import AppKit

/// Native Widget Market panel matching the Figma "Widget Market / Install /
/// Clean Editable" frame. The catalog is fetched from GlanceService and
/// rendered as native cards; install / uninstall mutates the local registry.
final class WidgetMarketPanel: NSPanel {
    static let shared = WidgetMarketPanel()

    private weak var attachedParent: NSWindow?
    private var manifests: [WidgetManifest] = []
    private var installedIDs: Set<String> = []
    private var isLoading = false
    private var hasAttemptedLoad = false
    private var selectedManifest: WidgetManifest?

    // Known official widgets. Used as the primary fetch IDs and as a hardcoded
    // offline fallback so the market never opens empty.
    private static let officialWidgets: [(id: String, name: String, summary: String, commandName: String, commandDescription: String, taskType: String, privacy: String)] = [
        ("a0d3311a-b952-4831-8ee4-69f72c381a88",
         "Remove Background",
         "Remove an image background while preserving fine subject edges.",
         "Remove Background",
         "Create a transparent-background copy of the selected image.",
         "image.remove-background.v1",
         "The selected image will be uploaded to Glance for cloud processing."),
        ("ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f",
         "超分",
         "图生图超分辨率，提升图片清晰度与细节。",
         "超分",
         "上传一张图片，生成更高分辨率的清晰版本。",
         "image.upscale.v1",
         "The selected image will be uploaded to Glance for cloud processing."),
        ("7cc3967a-60ac-4677-9817-72f57f5ef5fa",
         "RemoveBG 高级",
         "图生图高级背景移除，保留精细主体边缘。",
         "RemoveBG 高级",
         "上传一张图片，高级移除背景并生成透明背景副本。",
         "image.remove-bg-pro.v1",
         "The selected image will be uploaded to Glance for cloud processing.")
    ]
    private static let officialWidgetIDs: [String] = officialWidgets.map { $0.id }

    // MARK: - UI

    private let rootView = NSView()
    private let titleLabel = NSTextField(labelWithString: "Widget Market".localized)
    private let headerDivider = NSView()
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let catalogContainer = NSView()
    private let loadingOverlay = NSView()
    private let loadingSpinner = ModularImageLoadingView(frame: .zero)
    private let footerLabel = NSTextField(labelWithString: "")
    private let offlineLabel = NSTextField(labelWithString: "")
    private let detailView = WidgetMarketDetailView()

    // MARK: - Init

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 620),
                   styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)

        buildUI()
        refreshInstalledState()

        NotificationCenter.default.addObserver(
            self, selector: #selector(registryDidChange),
            name: WidgetRegistry.didChange, object: nil)
    }

    // MARK: - Public

    func toggle(from parent: NSWindow) {
        if isVisible, attachedParent === parent { close(); return }
        if let oldParent = attachedParent { oldParent.removeChildWindow(self) }
        attachedParent = parent
        position(alongside: parent)
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
        if manifests.isEmpty && !isLoading { loadCatalog() }
    }

    override func close() {
        if let attachedParent { attachedParent.removeChildWindow(self) }
        attachedParent = nil
        orderOut(nil)
    }

    // MARK: - Data

    private func loadCatalog() {
        guard !hasAttemptedLoad else { return }
        hasAttemptedLoad = true

        // Show hardcoded manifests immediately so the market never opens empty.
        // Then refresh with server manifests in the background.
        self.manifests = Self.makeOfflineManifests()
        self.refreshCatalog()
        refreshFromServer(showLoading: false)
    }

    private func refreshFromServer(showLoading: Bool) {
        guard !isLoading else { return }
        isLoading = true
        if showLoading { setLoading(true) }

        // Load the three known official widgets individually (the same API the
        // install path uses). If the network is down, any already-visible data
        // remains.
        let group = DispatchGroup()
        var manifests: [WidgetManifest] = []
        var errors: [Error] = []
        for id in Self.officialWidgetIDs {
            group.enter()
            WidgetCatalogClient.shared.fetch(widgetID: id) { result in
                switch result {
                case .success(let manifest): manifests.append(manifest)
                case .failure(let error): errors.append(error)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isLoading = false
            if showLoading { self.setLoading(false) }
            if !manifests.isEmpty {
                Logger.info("WidgetMarketPanel: refreshed \(manifests.count) widgets from server")
                self.manifests = manifests
                self.refreshCatalog()
            } else {
                Logger.info("WidgetMarketPanel: widget fetches failed: \(errors.map { $0.localizedDescription }.joined(separator: "; "))")
            }
        }
    }

    private static func makeOfflineManifests() -> [WidgetManifest] {
        officialWidgets.map {
            WidgetManifest(
                schemaVersion: 1,
                id: $0.id,
                version: "1.0.0",
                name: $0.name,
                summary: $0.summary,
                author: "Glance",
                iconURL: URL(string: "about:blank")!,
                official: true,
                execution: WidgetExecution(mode: "cloud"),
                commands: [
                    WidgetCommand(
                        id: $0.id,
                        name: $0.commandName,
                        description: $0.commandDescription,
                        inputTypes: ["image"],
                        inputMimeTypes: ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"],
                        outputs: ["image"],
                        taskType: $0.taskType,
                        requiresUpload: true,
                        parameterSchema: [:]
                    )
                ],
                privacy: WidgetPrivacy(uploadsMedia: true, notice: $0.privacy),
                minimumGlanceVersion: "2.0.0",
                updatedAt: "",
                signature: WidgetSignature(algorithm: "Ed25519", keyID: "", value: "")
            )
        }
    }

    private func refreshInstalledState() {
        installedIDs = Set(WidgetRegistry.shared.installed.map { $0.id })
        refreshCatalog()
    }

    @objc private func registryDidChange() {
        refreshInstalledState()
    }

    // MARK: - UI Builders

    private func buildUI() {
        let panelSize = NSSize(width: 380, height: 620)

        // Shadow wrapper + clipped content, same pattern as ImageInfoPanel.
        let wrapper = NSView(frame: NSRect(origin: .zero, size: panelSize))
        wrapper.wantsLayer = true
        wrapper.layer?.masksToBounds = false
        wrapper.layer?.shadowColor = NSColor.black.withAlphaComponent(0.32).cgColor
        wrapper.layer?.shadowOffset = CGSize(width: 0, height: -12)
        wrapper.layer?.shadowRadius = 28
        wrapper.layer?.shadowOpacity = 1

        rootView.frame = wrapper.bounds
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 16
        rootView.layer?.masksToBounds = true
        rootView.layer?.borderWidth = 1
        rootView.layer?.borderColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
        rootView.autoresizingMask = [.width, .height]
        wrapper.addSubview(rootView)

        // Solid black base matching Figma: #090a0d with a warm #2b211d tint at
        // 24% opacity. This is NOT frosted glass — the design is an opaque
        // dark panel.
        let base = NSView()
        base.wantsLayer = true
        base.layer?.backgroundColor = NSColor(srgbRed: 9 / 255, green: 10 / 255, blue: 13 / 255, alpha: 1).cgColor
        base.layer?.cornerRadius = 16
        base.frame = rootView.bounds
        base.autoresizingMask = [.width, .height]
        rootView.addSubview(base)

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(srgbRed: 43 / 255, green: 33 / 255, blue: 29 / 255, alpha: 0.24).cgColor
        tint.layer?.cornerRadius = 16
        tint.frame = rootView.bounds
        tint.autoresizingMask = [.width, .height]
        rootView.addSubview(tint)

        contentView = wrapper

        // Title
        titleLabel.font = PanelStyle.inspectFont(ofSize: 21, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        rootView.addSubview(titleLabel)

        // Header divider
        headerDivider.wantsLayer = true
        headerDivider.layer?.backgroundColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
        rootView.addSubview(headerDivider)

        // Close / refresh buttons
        for (button, symbol) in [(closeButton, "xmark"), (refreshButton, "arrow.clockwise")] {
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageOnly
            button.contentTintColor = PanelStyle.textPrimary
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(srgbRed: 44 / 255, green: 45 / 255, blue: 49 / 255, alpha: 1).cgColor
            button.layer?.borderWidth = 1
            button.layer?.borderColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
            button.layer?.cornerRadius = 8
            button.target = self
            rootView.addSubview(button)
        }
        closeButton.action = #selector(closeTapped)
        closeButton.toolTip = "Close".localized
        refreshButton.action = #selector(refreshTapped)
        refreshButton.toolTip = "Refresh".localized

        // Catalog scroll view
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = catalogContainer
        rootView.addSubview(scrollView)

        // Footer labels
        footerLabel.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        footerLabel.textColor = PanelStyle.textTertiary
        footerLabel.stringValue = "OFFICIAL WIDGETS"
        rootView.addSubview(footerLabel)

        offlineLabel.font = PanelStyle.inspectFont(ofSize: 11)
        offlineLabel.textColor = PanelStyle.textSecondary
        offlineLabel.lineBreakMode = .byWordWrapping
        offlineLabel.maximumNumberOfLines = 0
        offlineLabel.stringValue = "Installed Widgets remain available when the catalog is offline.".localized
        rootView.addSubview(offlineLabel)

        // Loading overlay
        loadingOverlay.wantsLayer = true
        loadingOverlay.layer?.backgroundColor = NSColor(srgbRed: 9 / 255, green: 10 / 255, blue: 13 / 255, alpha: 0.94).cgColor
        rootView.addSubview(loadingOverlay)
        loadingSpinner.setLoading(true)
        loadingOverlay.addSubview(loadingSpinner)
        setLoading(false)

        // Detail view (initially hidden)
        detailView.isHidden = true
        detailView.onBack = { [weak self] in self?.showCatalog() }
        detailView.onInstall = { [weak self] id in
            guard let self, let manifest = self.manifests.first(where: { $0.id == id }) else { return }
            self.install(manifest)
        }
        detailView.onUninstall = { [weak self] id in
            WidgetRegistry.shared.uninstall(id: id)
            self?.refreshInstalledState()
            self?.showCatalog()
        }
        rootView.addSubview(detailView)

        layoutContent()
    }

    private func layoutContent() {
        let W: CGFloat = 380
        let H: CGFloat = 620

        titleLabel.frame = NSRect(x: 21, y: H - 44, width: 200, height: 25)
        headerDivider.frame = NSRect(x: 19, y: H - 69, width: 340, height: 1)

        // Figma: Close (left) at x=294, Refresh (right) at x=334.
        closeButton.frame = NSRect(x: W - 86, y: H - 53, width: 38, height: 38)
        refreshButton.frame = NSRect(x: W - 46, y: H - 53, width: 38, height: 38)

        // Figma: cards start at panel top 84 and end near panel top 500.
        let topPad: CGFloat = 84
        let bottomPad: CGFloat = 116
        scrollView.frame = NSRect(x: 0, y: bottomPad, width: W, height: H - topPad - bottomPad)

        footerLabel.frame = NSRect(x: 19, y: 82, width: 340, height: 12)
        offlineLabel.frame = NSRect(x: 19, y: 56, width: 340, height: 13)

        loadingOverlay.frame = NSRect(x: 0, y: 0, width: W, height: H)
        loadingSpinner.frame = NSRect(x: (W - ModularImageLoadingView.preferredSize.width) / 2,
                                      y: (H - ModularImageLoadingView.preferredSize.height) / 2,
                                      width: ModularImageLoadingView.preferredSize.width,
                                      height: ModularImageLoadingView.preferredSize.height)

        detailView.frame = NSRect(x: 0, y: 0, width: W, height: H)
    }

    private func refreshCatalog() {
        // Clear existing cards.
        for view in catalogContainer.subviews { view.removeFromSuperview() }

        let cardW: CGFloat = 348
        let cardH: CGFloat = 132
        let spacing: CGFloat = 12
        let topInset: CGFloat = 0
        let bottomInset: CGFloat = 0
        let contentH = topInset + CGFloat(manifests.count) * cardH + CGFloat(max(0, manifests.count - 1)) * spacing + bottomInset
        catalogContainer.frame = NSRect(x: 0, y: 0, width: 380, height: contentH)

        for (index, manifest) in manifests.enumerated() {
            let card = WidgetMarketCardView(manifest: manifest, isInstalled: installedIDs.contains(manifest.id))
            card.onTap = { [weak self] in self?.showDetail(for: manifest) }
            card.onInstall = { [weak self] in self?.install(manifest) }
            let y = contentH - topInset - CGFloat(index + 1) * cardH - CGFloat(index) * spacing
            card.frame = NSRect(x: 16, y: y, width: cardW, height: cardH)
            catalogContainer.addSubview(card)
        }

        let total = manifests.count
        footerLabel.stringValue = String(format: "OFFICIAL WIDGETS  ·  %d AVAILABLE".localized, total)
    }

    private func showDetail(for manifest: WidgetManifest) {
        selectedManifest = manifest
        detailView.configure(manifest: manifest, isInstalled: installedIDs.contains(manifest.id))
        detailView.isHidden = false
        scrollView.isHidden = true
        footerLabel.isHidden = true
        offlineLabel.isHidden = true
    }

    private func showCatalog() {
        selectedManifest = nil
        detailView.isHidden = true
        scrollView.isHidden = false
        footerLabel.isHidden = false
        offlineLabel.isHidden = false
    }

    private func showOfflineState() {
        footerLabel.stringValue = "OFFICIAL WIDGETS  ·  0 AVAILABLE".localized
    }

    private func setLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
    }

    // MARK: - Actions

    @objc private func closeTapped() { close() }

    @objc private func refreshTapped() {
        hasAttemptedLoad = true
        refreshFromServer(showLoading: true)
    }

    private func install(_ manifest: WidgetManifest) {
        WidgetCatalogClient.shared.fetch(widgetID: manifest.id) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let fullManifest):
                WidgetRegistry.shared.install(fullManifest)
                self.refreshInstalledState()
            case .failure(let error):
                Logger.info("WidgetMarketPanel: install failed: \(error.localizedDescription)")
            }
        }
    }

    private func uninstall(_ id: String) {
        WidgetRegistry.shared.uninstall(id: id)
        refreshInstalledState()
    }

    private func position(alongside parent: NSWindow) {
        let gap: CGFloat = 2
        let width: CGFloat = 380
        let height: CGFloat = 620
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        var x = parent.frame.maxX + gap
        if x + width > visible.maxX { x = max(visible.minX, parent.frame.minX - width - gap) }
        x = max(visible.minX, min(x, visible.maxX - width))
        // Child panels align with the parent's top edge, not its bottom edge.
        let y = max(visible.minY, min(parent.frame.maxY - height, visible.maxY - height))
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

// MARK: - Catalog card

private final class WidgetMarketCardView: NSView {
    var onTap: (() -> Void)?
    var onInstall: (() -> Void)?

    private let manifest: WidgetManifest
    private let isInstalled: Bool

    private let iconView = WidgetMarketIconView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    private let cloudBadge = WidgetMarketTextView()
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let footerDivider = NSView()
    private let commandsLabel = NSTextField(labelWithString: "")
    private let installButton = WidgetMarketActionButton()
    private let installedBadge = WidgetMarketTextView()

    init(manifest: WidgetManifest, isInstalled: Bool) {
        self.manifest = manifest
        self.isInstalled = isInstalled
        super.init(frame: NSRect(x: 0, y: 0, width: 348, height: 132))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        setupAppearance()
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 348, height: 132) }

    private func setupAppearance() {
        if isInstalled {
            layer?.backgroundColor = NSColor(srgbRed: 33 / 255, green: 28 / 255, blue: 26 / 255, alpha: 1).cgColor
            layer?.borderColor = NSColor(srgbRed: 232 / 255, green: 168 / 255, blue: 124 / 255, alpha: 0.45).cgColor
        } else {
            layer?.backgroundColor = NSColor(srgbRed: 23 / 255, green: 24 / 255, blue: 29 / 255, alpha: 1).cgColor
            layer?.borderColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
        }
    }

    private func buildUI() {
        iconView.letter = String(manifest.name.prefix(1)).uppercased()
        iconView.frame = NSRect(x: 13, y: 71, width: 48, height: 48)
        addSubview(iconView)

        nameLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = PanelStyle.textPrimary
        nameLabel.stringValue = manifest.name
        nameLabel.frame = NSRect(x: 73, y: 105, width: 215, height: 16)
        addSubview(nameLabel)

        versionLabel.font = PanelStyle.inspectFont(ofSize: 10)
        versionLabel.textColor = PanelStyle.textTertiary
        versionLabel.stringValue = "Official Widget  ·  v\(manifest.version)"
        versionLabel.frame = NSRect(x: 73, y: 85, width: 180, height: 12)
        addSubview(versionLabel)

        cloudBadge.string = "CLOUD"
        cloudBadge.font = PanelStyle.inspectFont(ofSize: 9, weight: .semibold)
        cloudBadge.textColor = PanelStyle.accent
        cloudBadge.wantsLayer = true
        cloudBadge.layer?.backgroundColor = NSColor(srgbRed: 58 / 255, green: 44 / 255, blue: 38 / 255, alpha: 1).cgColor
        cloudBadge.layer?.cornerRadius = 4
        cloudBadge.frame = NSRect(x: 277, y: 98, width: 55, height: 19)
        addSubview(cloudBadge)

        summaryLabel.font = PanelStyle.inspectFont(ofSize: 11)
        summaryLabel.textColor = PanelStyle.textSecondary
        summaryLabel.stringValue = manifest.summary
        summaryLabel.maximumNumberOfLines = 2
        // Figma: Summary top=67, height=13. Keep it as a single measured row;
        // the card copy in the reference is not a two-line block.
        summaryLabel.frame = NSRect(x: 13, y: 52, width: 316, height: 13)
        addSubview(summaryLabel)

        footerDivider.wantsLayer = true
        footerDivider.layer?.backgroundColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
        footerDivider.frame = NSRect(x: 13, y: 40, width: 320, height: 1)
        addSubview(footerDivider)

        commandsLabel.font = PanelStyle.inspectFont(ofSize: 10)
        commandsLabel.textColor = PanelStyle.textTertiary
        let commandNames = manifest.commands.map { $0.name }.joined(separator: " · ")
        commandsLabel.stringValue = "\(manifest.commands.count) command\(manifest.commands.count == 1 ? "" : "s")  ·  \(commandNames)"
        commandsLabel.frame = NSRect(x: 13, y: 18, width: 218, height: 12)
        addSubview(commandsLabel)

        if isInstalled {
            installedBadge.string = "Installed".localized
            installedBadge.font = PanelStyle.inspectFont(ofSize: 11, weight: .semibold)
            installedBadge.textColor = NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 175 / 255, alpha: 1)
            installedBadge.wantsLayer = true
            installedBadge.layer?.backgroundColor = NSColor(srgbRed: 27 / 255, green: 48 / 255, blue: 41 / 255, alpha: 1).cgColor
            installedBadge.layer?.borderWidth = 1
            installedBadge.layer?.borderColor = NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 175 / 255, alpha: 0.5).cgColor
            installedBadge.layer?.cornerRadius = 8
            installedBadge.frame = NSRect(x: 242, y: 6, width: 91, height: 31)
            addSubview(installedBadge)
        } else {
            installButton.style = .install
            installButton.target = self
            installButton.action = #selector(installTapped)
            installButton.frame = NSRect(x: 257, y: 6, width: 76, height: 31)
            addSubview(installButton)
        }
    }

    @objc private func installTapped() { onInstall?() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let the Install button receive its own events; everything else on the
        // card routes to the card itself so the detail drawer opens.
        guard let superview else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        if !isInstalled, installButton.frame.contains(local) { return installButton }
        return bounds.contains(local) ? self : super.hitTest(point)
    }

    private var mouseDownPoint: NSPoint = .zero
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if abs(point.x - mouseDownPoint.x) < 4, abs(point.y - mouseDownPoint.y) < 4 {
            onTap?()
        }
    }
}

// MARK: - Icon view

private final class WidgetMarketIconView: NSView {
    var letter: String = "W" {
        didSet { letterLabel.stringValue = letter }
    }

    private let letterLabel = NSTextField(labelWithString: "W")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 42 / 255, green: 36 / 255, blue: 35 / 255, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
        layer?.cornerRadius = 10

        letterLabel.font = PanelStyle.inspectFont(ofSize: 15, weight: .semibold)
        letterLabel.textColor = PanelStyle.accent
        letterLabel.alignment = .center
        addSubview(letterLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        letterLabel.frame = bounds
    }
}

// MARK: - Action button

private final class WidgetMarketActionButton: NSButton {
    enum Style { case install, installed, uninstall }

    var style: Style = .install {
        didSet { applyStyle() }
    }
    private let titleView = WidgetMarketTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .texturedRounded
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        title = ""
        addSubview(titleView)
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyStyle() {
        switch style {
        case .install:
            titleView.string = "Install".localized
            titleView.textColor = PanelStyle.accentInk
            titleView.font = PanelStyle.inspectFont(ofSize: 11, weight: .semibold)
            layer?.backgroundColor = PanelStyle.accent.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = PanelStyle.accent.withAlphaComponent(0.5).cgColor
        case .installed:
            titleView.string = "Installed".localized
            titleView.textColor = NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 175 / 255, alpha: 1)
            titleView.font = PanelStyle.inspectFont(ofSize: 11, weight: .semibold)
            layer?.backgroundColor = NSColor(srgbRed: 27 / 255, green: 48 / 255, blue: 41 / 255, alpha: 1).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 175 / 255, alpha: 0.5).cgColor
        case .uninstall:
            titleView.string = "Uninstall Widget".localized
            titleView.textColor = PanelStyle.failure
            titleView.font = PanelStyle.inspectFont(ofSize: 11, weight: .medium)
            layer?.backgroundColor = NSColor(srgbRed: 35 / 255, green: 23 / 255, blue: 25 / 255, alpha: 1).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(srgbRed: 241 / 255, green: 139 / 255, blue: 134 / 255, alpha: 0.42).cgColor
        }
        setAccessibilityLabel(titleView.string)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        // Figma text node: x=0, y=8, width=button width, height=13 for the
        // 31pt catalog actions; the 38pt detail action uses y=11, h=13.
        let textHeight: CGFloat = 13
        let textY: CGFloat = bounds.height >= 38 ? 11 : 8
        titleView.frame = NSRect(x: 0, y: textY, width: bounds.width, height: textHeight)
    }
}

private final class WidgetMarketTextView: NSView {
    var string = "" { didSet { needsDisplay = true } }
    var font = PanelStyle.inspectFont(ofSize: 11) { didSet { needsDisplay = true } }
    var textColor = NSColor.white { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard !string.isEmpty else { return }
        let text = NSAttributedString(string: string,
                                      attributes: [.font: font, .foregroundColor: textColor])
        let layout = NSLayoutManager()
        let storage = NSTextStorage(attributedString: text)
        let container = NSTextContainer(size: bounds.size)
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let glyphRange = layout.glyphRange(for: container)
        let used = layout.boundingRect(forGlyphRange: glyphRange, in: container)
        let origin = NSPoint(x: floor(bounds.midX - used.midX),
                             y: floor(bounds.midY - used.midY))
        layout.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}


// MARK: - Detail view

private final class WidgetMarketDetailView: NSView {
    var onBack: (() -> Void)?
    var onInstall: ((String) -> Void)?
    var onUninstall: ((String) -> Void)?

    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let headingLabel = NSTextField(labelWithString: "Widget details".localized)
    private let headerDivider = NSView()
    private let iconView = WidgetMarketIconView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    private let cloudBadge = WidgetMarketTextView()
    private let installedBadge = WidgetMarketTextView()
    private let summaryDivider = NSView()
    private let aboutHeading = NSTextField(labelWithString: "ABOUT".localized)
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let commandHeading = NSTextField(labelWithString: "COMMAND".localized)
    private let commandLabel = NSTextField(wrappingLabelWithString: "")
    private let privacyHeading = NSTextField(labelWithString: "PRIVACY".localized)
    private let privacyLabel = NSTextField(wrappingLabelWithString: "")
    private let bottomDivider = NSView()
    private let installButton = WidgetMarketActionButton()
    private let uninstallButton = WidgetMarketActionButton()

    private var manifestID: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        backButton.bezelStyle = .texturedRounded
        backButton.isBordered = false
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        backButton.imagePosition = .imageOnly
        backButton.contentTintColor = PanelStyle.textPrimary
        backButton.wantsLayer = true
        backButton.layer?.backgroundColor = NSColor(srgbRed: 44 / 255, green: 45 / 255, blue: 49 / 255, alpha: 1).cgColor
        backButton.layer?.borderWidth = 1
        backButton.layer?.borderColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
        backButton.layer?.cornerRadius = 8
        backButton.target = self
        backButton.action = #selector(backTapped)
        addSubview(backButton)

        headingLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        headingLabel.textColor = PanelStyle.textSecondary
        addSubview(headingLabel)

        headerDivider.wantsLayer = true
        headerDivider.layer?.backgroundColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
        addSubview(headerDivider)

        iconView.frame = NSRect(x: 22, y: 479, width: 48, height: 48)
        addSubview(iconView)

        nameLabel.font = PanelStyle.inspectFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = PanelStyle.textPrimary
        addSubview(nameLabel)

        versionLabel.font = PanelStyle.inspectFont(ofSize: 11)
        versionLabel.textColor = PanelStyle.textTertiary
        addSubview(versionLabel)

        cloudBadge.string = "CLOUD"
        cloudBadge.font = PanelStyle.inspectFont(ofSize: 9, weight: .semibold)
        cloudBadge.textColor = PanelStyle.accent
        cloudBadge.wantsLayer = true
        cloudBadge.layer?.backgroundColor = NSColor(srgbRed: 58 / 255, green: 44 / 255, blue: 38 / 255, alpha: 1).cgColor
        cloudBadge.layer?.cornerRadius = 4
        addSubview(cloudBadge)

        installedBadge.font = PanelStyle.inspectFont(ofSize: 11, weight: .semibold)
        installedBadge.textColor = NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 175 / 255, alpha: 1)
        installedBadge.string = "Installed".localized
        installedBadge.wantsLayer = true
        installedBadge.layer?.backgroundColor = NSColor(srgbRed: 27 / 255, green: 48 / 255, blue: 41 / 255, alpha: 1).cgColor
        installedBadge.layer?.borderWidth = 1
        installedBadge.layer?.borderColor = NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 175 / 255, alpha: 0.5).cgColor
        installedBadge.layer?.cornerRadius = 8
        addSubview(installedBadge)

        summaryDivider.wantsLayer = true
        summaryDivider.layer?.backgroundColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
        addSubview(summaryDivider)

        aboutHeading.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        aboutHeading.textColor = PanelStyle.textTertiary
        addSubview(aboutHeading)

        summaryLabel.font = PanelStyle.inspectFont(ofSize: 12)
        summaryLabel.textColor = PanelStyle.textSecondary
        summaryLabel.maximumNumberOfLines = 0
        addSubview(summaryLabel)

        commandHeading.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        commandHeading.textColor = PanelStyle.textTertiary
        addSubview(commandHeading)

        commandLabel.font = PanelStyle.inspectFont(ofSize: 11)
        commandLabel.textColor = PanelStyle.textSecondary
        commandLabel.maximumNumberOfLines = 0
        addSubview(commandLabel)

        privacyHeading.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        privacyHeading.textColor = PanelStyle.textTertiary
        addSubview(privacyHeading)

        privacyLabel.font = PanelStyle.inspectFont(ofSize: 11)
        privacyLabel.textColor = PanelStyle.textSecondary
        privacyLabel.maximumNumberOfLines = 0
        addSubview(privacyLabel)

        bottomDivider.wantsLayer = true
        bottomDivider.layer?.backgroundColor = NSColor(srgbRed: 52 / 255, green: 53 / 255, blue: 58 / 255, alpha: 1).cgColor
        addSubview(bottomDivider)

        installButton.style = .install
        installButton.target = self
        installButton.action = #selector(installTapped)
        addSubview(installButton)

        uninstallButton.style = .uninstall
        uninstallButton.target = self
        uninstallButton.action = #selector(uninstallTapped)
        addSubview(uninstallButton)

        layoutContent()
    }

    private func layoutContent() {
        let W = bounds.width
        let H = bounds.height

        backButton.frame = NSRect(x: 19, y: H - 54, width: 38, height: 38)
        headingLabel.frame = NSRect(x: 73, y: H - 41, width: 200, height: 16)
        headerDivider.frame = NSRect(x: 19, y: H - 69, width: 340, height: 1)

        iconView.frame = NSRect(x: 21, y: H - 140, width: 48, height: 48)
        nameLabel.frame = NSRect(x: 83, y: H - 114, width: 250, height: 19)
        versionLabel.frame = NSRect(x: 83, y: H - 135, width: 250, height: 13)
        cloudBadge.frame = NSRect(x: 21, y: H - 178, width: 55, height: 19)
        installedBadge.frame = NSRect(x: W - 112, y: H - 184, width: 91, height: 31)

        summaryDivider.frame = NSRect(x: 21, y: H - 199, width: 336, height: 1)
        aboutHeading.frame = NSRect(x: 21, y: H - 230, width: 336, height: 12)
        summaryLabel.frame = NSRect(x: 21, y: H - 272, width: 334, height: 30)

        commandHeading.frame = NSRect(x: 21, y: H - 323, width: 336, height: 12)
        commandLabel.frame = NSRect(x: 21, y: H - 348, width: 334, height: 13)

        privacyHeading.frame = NSRect(x: 21, y: H - 402, width: 336, height: 12)
        privacyLabel.frame = NSRect(x: 21, y: H - 427, width: 334, height: 13)

        bottomDivider.frame = NSRect(x: 21, y: H - 517, width: 336, height: 1)
        installButton.frame = NSRect(x: 21, y: H - 575, width: 336, height: 38)
        uninstallButton.frame = NSRect(x: 21, y: H - 575, width: 336, height: 38)
    }

    func configure(manifest: WidgetManifest, isInstalled: Bool) {
        manifestID = manifest.id
        iconView.letter = String(manifest.name.prefix(1)).uppercased()
        nameLabel.stringValue = manifest.name
        versionLabel.stringValue = "Official Widget  ·  v\(manifest.version)"
        summaryLabel.stringValue = manifest.summary
        let command = manifest.commands.first
        let commandText = command.map { "\($0.name)  ·  \($0.description)" } ?? ""
        commandLabel.stringValue = commandText
        privacyLabel.stringValue = manifest.privacy.notice
        installedBadge.isHidden = !isInstalled
        installButton.isHidden = isInstalled
        uninstallButton.isHidden = !isInstalled
    }

    @objc private func backTapped() { onBack?() }
    @objc private func installTapped() { onInstall?(manifestID) }
    @objc private func uninstallTapped() { onUninstall?(manifestID) }

    override func layout() {
        super.layout()
        layoutContent()
    }
}
