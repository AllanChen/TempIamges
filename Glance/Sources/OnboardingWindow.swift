import AppKit

final class OnboardingWindow: NSWindow {
    private static let designSize = NSSize(width: 580, height: 650)

    private let root = NSView()
    private let titlebar = OnboardingTitlebar()
    private let windowTitle = NSTextField(labelWithString: "Welcome to Glance".localized)
    private let body = NSView()
    private let appMark = NSView()
    private let markTile = NSView()
    private let markIcon = NSImageView()
    private let heading = NSTextField(labelWithString: "Set up essential permissions".localized)
    private let explanation = NSTextField(wrappingLabelWithString:
        "Glance needs permission to read the current selection and respond to your keyboard shortcut. You can change these settings later.".localized)
    private let permissionList = NSView()
    private let accessibilityRow = PermissionStatusView(
        symbol: "A", title: "Accessibility".localized,
        description: "Read the current selection".localized)
    private let inputMonitoringRow = PermissionStatusView(
        symbol: "I", title: "Input Monitoring".localized,
        description: "Recognize the global shortcut".localized)
    private let fullDiskAccessRow = PermissionStatusView(
        symbol: "F", title: "Full Disk Access".localized,
        description: "Preview files in protected locations".localized, optional: true)
    private let continueButton = PanelStyle.makePrimaryButton(title: "Continue".localized, target: nil, action: nil)
    private let footnote = NSTextField(labelWithString:
        "Permissions stay under your control in macOS System Settings.".localized)
    private var permissionCheckGeneration = UUID()

    init() {
        let initial = ScreenManager.shared.contentFrame(for: Self.designSize)
        super.init(contentRect: initial,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Welcome to Glance".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = PanelStyle.inspectBackground
        contentAspectRatio = Self.designSize
        minSize = NSSize(width: min(480, initial.width), height: min(538, initial.height))
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        buildUI()
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPermissionStatus),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPermissionStatus),
                                               name: NSWindow.didBecomeKeyNotification, object: self)
        updatePermissionStatus()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildUI() {
        contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectBackground)
        root.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        root.layer?.borderWidth = 1
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true

        configureLabel(windowTitle, size: 12, color: PanelStyle.textPrimary,
                       weight: .semibold, alignment: .center)
        titlebar.addSubview(windowTitle)
        let traffic: [(String, NSColor, Selector)] = [
            ("Close".localized, NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), #selector(closeTapped)),
            ("Minimize".localized, NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), #selector(minimizeTapped)),
            ("Zoom".localized, NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), #selector(zoomTapped))
        ]
        for (label, color, action) in traffic {
            let control = NSButton()
            control.isBordered = false
            control.title = ""
            control.toolTip = label
            control.setAccessibilityLabel(label)
            control.target = self
            control.action = action
            control.wantsLayer = true
            control.layer?.backgroundColor = PanelStyle.resolvedCG(color)
            titlebar.addSubview(control)
        }
        root.addSubview(titlebar)

        body.wantsLayer = true
        body.layer?.backgroundColor = PanelStyle.resolvedCG(
            NSColor(srgbRed: 11 / 255, green: 12 / 255, blue: 15 / 255, alpha: 1))
        root.addSubview(body)

        appMark.wantsLayer = true
        appMark.layer?.backgroundColor = PanelStyle.resolvedCG(
            NSColor(srgbRed: 58 / 255, green: 44 / 255, blue: 38 / 255, alpha: 1))
        appMark.layer?.cornerRadius = 16
        body.addSubview(appMark)
        markTile.wantsLayer = true
        markTile.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        markTile.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.accent.withAlphaComponent(0.58))
        markTile.layer?.borderWidth = 1
        markTile.layer?.cornerRadius = 8
        appMark.addSubview(markTile)
        markIcon.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Glance")
        markIcon.contentTintColor = PanelStyle.accent
        markIcon.imageScaling = .scaleProportionallyUpOrDown
        markTile.addSubview(markIcon)

        configureLabel(heading, size: 20, color: PanelStyle.textPrimary,
                       weight: .semibold, alignment: .center)
        configureLabel(explanation, size: 12, color: PanelStyle.textSecondary, alignment: .center)
        explanation.maximumNumberOfLines = 0
        explanation.lineBreakMode = .byWordWrapping
        body.addSubview(heading)
        body.addSubview(explanation)

        permissionList.wantsLayer = true
        permissionList.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        body.addSubview(permissionList)
        accessibilityRow.onOpenSettings = { PermissionManager.shared.openAccessibilitySettings() }
        inputMonitoringRow.onOpenSettings = { PermissionManager.shared.openInputMonitoringSettings() }
        fullDiskAccessRow.onOpenSettings = { PermissionManager.shared.openFullDiskAccessSettings() }
        [accessibilityRow, inputMonitoringRow, fullDiskAccessRow].forEach(permissionList.addSubview)

        continueButton.target = self
        continueButton.action = #selector(continuePressed)
        continueButton.isEnabled = false
        continueButton.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
        body.addSubview(continueButton)
        configureLabel(footnote, size: 10, color: PanelStyle.textTertiary, alignment: .center)
        body.addSubview(footnote)
        layoutContent()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutContent()
    }

    private func layoutContent() {
        let size = root.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let sx = size.width / Self.designSize.width
        let sy = size.height / Self.designSize.height
        let scale = min(sx, sy)
        root.layer?.cornerRadius = 16 * scale
        root.layer?.borderWidth = max(1, scale)
        titlebar.frame = NSRect(x: 0, y: size.height - 44 * sy,
                                width: size.width, height: 44 * sy)
        windowTitle.font = PanelStyle.inspectFont(ofSize: 12 * scale, weight: .semibold)
        windowTitle.frame = NSRect(x: 0, y: 16 * sy, width: size.width, height: 15 * sy)
        for (index, button) in titlebar.subviews.compactMap({ $0 as? NSButton }).enumerated() {
            button.frame = NSRect(x: CGFloat(16 + index * 18) * sx, y: 16 * sy,
                                  width: 11 * sx, height: 11 * sy)
            button.layer?.cornerRadius = 5.5 * scale
        }
        body.frame = NSRect(x: 0, y: 0, width: size.width, height: 606 * sy)
        func fromTop(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * sx, y: body.bounds.height - (y + h) * sy,
                   width: w * sx, height: h * sy)
        }
        appMark.frame = fromTop(256, 32, 68, 68)
        appMark.layer?.cornerRadius = 16 * scale
        markTile.frame = NSRect(x: 15 * sx, y: 15 * sy, width: 38 * sx, height: 38 * sy)
        markTile.layer?.cornerRadius = 8 * scale
        markIcon.frame = NSRect(x: 10 * sx, y: 10 * sy, width: 18 * sx, height: 18 * sy)
        heading.font = PanelStyle.inspectFont(ofSize: 20 * scale, weight: .semibold)
        heading.frame = fromTop(0, 125, 580, 27)
        explanation.font = PanelStyle.inspectFont(ofSize: 12 * scale)
        explanation.frame = fromTop(75, 164, 430, 58)
        permissionList.frame = fromTop(56, 230, 468, 240)
        accessibilityRow.frame = NSRect(x: 0, y: 170 * sy, width: 468 * sx, height: 70 * sy)
        inputMonitoringRow.frame = NSRect(x: 0, y: 90 * sy, width: 468 * sx, height: 70 * sy)
        fullDiskAccessRow.frame = NSRect(x: 0, y: 10 * sy, width: 468 * sx, height: 70 * sy)
        continueButton.frame = fromTop(76, 512, 428, 38)
        continueButton.layer?.cornerRadius = 8 * scale
        footnote.font = PanelStyle.inspectFont(ofSize: 10 * scale)
        footnote.frame = fromTop(0, 565, 580, 15)
    }

    private func configureLabel(_ label: NSTextField, size: CGFloat, color: NSColor,
                                weight: NSFont.Weight = .regular,
                                alignment: NSTextAlignment = .left) {
        label.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
    }

    private func updatePermissionStatus() {
        let manager = PermissionManager.shared
        let accessibility = manager.isAccessibilityGranted
        let inputMonitoring = manager.isInputMonitoringGranted
        accessibilityRow.updateStatus(granted: accessibility)
        inputMonitoringRow.updateStatus(granted: inputMonitoring)
        continueButton.isEnabled = accessibility && inputMonitoring
        continueButton.alphaValue = continueButton.isEnabled ? 1 : 0.45

        let generation = UUID()
        permissionCheckGeneration = generation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let granted = PermissionManager.shared.isFullDiskAccessGranted
            DispatchQueue.main.async {
                guard let self, self.permissionCheckGeneration == generation else { return }
                self.fullDiskAccessRow.updateStatus(granted: granted)
            }
        }
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        updatePermissionStatus()
    }

    @objc func refreshPermissionStatus() {
        guard isVisible else { return }
        updatePermissionStatus()
    }
    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }
    @objc private func continuePressed() { close() }

    override func close() {
        permissionCheckGeneration = UUID()
        super.close()
    }
}

private final class OnboardingTitlebar: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) }
        else { window?.performDrag(with: event) }
    }
}

final class PermissionStatusView: NSView {
    var onOpenSettings: (() -> Void)?

    private let symbol: String
    private let optional: Bool
    private let symbolBackground = NSView()
    private let symbolLabel = NSTextField(labelWithString: "")
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let statusButton = PanelStyle.makeQuietButton(title: "", target: nil, action: nil)
    private let separator = NSView()
    private var granted = false

    init(symbol: String, title: String, description: String, optional: Bool = false) {
        self.symbol = symbol
        self.optional = optional
        titleLabel = NSTextField(labelWithString: title)
        detailLabel = NSTextField(labelWithString: description)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        symbolBackground.wantsLayer = true
        symbolBackground.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        symbolBackground.layer?.cornerRadius = 10
        addSubview(symbolBackground)
        symbolLabel.stringValue = symbol
        symbolLabel.alignment = .center
        symbolLabel.textColor = PanelStyle.textSecondary
        symbolBackground.addSubview(symbolLabel)
        titleLabel.textColor = PanelStyle.textPrimary
        detailLabel.textColor = PanelStyle.textTertiary
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        addSubview(detailLabel)
        statusButton.target = self
        statusButton.action = #selector(statusTapped)
        statusButton.setAccessibilityLabel(title)
        addSubview(statusButton)
        separator.wantsLayer = true
        separator.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        addSubview(separator)
        updateStatus(granted: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let sx = bounds.width / 468
        let sy = bounds.height / 70
        let scale = min(sx, sy)
        symbolBackground.frame = NSRect(x: 0, y: 15 * sy, width: 40 * sx, height: 40 * sy)
        symbolBackground.layer?.cornerRadius = 10 * scale
        symbolLabel.font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .semibold)
        symbolLabel.frame = NSRect(x: 0, y: 12 * sy, width: 40 * sx, height: 16 * sy)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .semibold)
        titleLabel.frame = NSRect(x: 54 * sx, y: 42 * sy, width: 284 * sx, height: 17 * sy)
        detailLabel.font = PanelStyle.inspectFont(ofSize: 11 * scale)
        detailLabel.frame = NSRect(x: 54 * sx, y: 19 * sy, width: 284 * sx, height: 14 * sy)
        statusButton.titleFont = PanelStyle.inspectFont(ofSize: 11 * scale, weight: .medium)
        statusButton.frame = NSRect(x: 354 * sx, y: 18 * sy, width: 114 * sx, height: 34 * sy)
        statusButton.layer?.cornerRadius = 8 * scale
        separator.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(1, sy))
    }

    func updateStatus(granted: Bool) {
        self.granted = granted
        let value = granted ? "Allowed".localized
            : (optional ? "Optional".localized : "Open Settings".localized)
        statusButton.title = value
        statusButton.titleColor = granted ? PanelStyle.success : PanelStyle.accent
        statusButton.normalBackground = granted
            ? NSColor(srgbRed: 23 / 255, green: 48 / 255, blue: 39 / 255, alpha: 1)
            : PanelStyle.inspectToolbar
        statusButton.hoverBackground = granted
            ? statusButton.normalBackground
            : PanelStyle.surfaceElevated
        statusButton.layer?.borderWidth = 0
        statusButton.toolTip = granted ? "" : "Open Settings".localized
        statusButton.setAccessibilityLabel("\(titleLabel.stringValue), \(value)")
    }

    @objc private func statusTapped() {
        guard !granted else { return }
        onOpenSettings?()
    }
}
