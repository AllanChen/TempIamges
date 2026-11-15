import AppKit

final class OnboardingWindow: NSWindow {
    /// Posted when the permission guide is dismissed, whichever way.
    static let didClose = Notification.Name("GlanceOnboardingDidClose")
    /// Figma `12 · Onboarding / Permissions` (640 × 620). Peek needs only
    /// Accessibility, which also covers event listening, so the Input
    /// Monitoring row is not shown; the free space stays above the actions.
    private static let designSize = NSSize(width: 640, height: 620)

    private let root = NSView()
    private let titlebar = OnboardingTitlebar()
    private let heading = NSTextField(labelWithString: "Set up permissions".localized)
    private let explanation = NSTextField(wrappingLabelWithString:
        "Permissions enable shortcuts and access to protected files. You can skip setup and keep using Glance.".localized)
    private let accessibilityRow = PermissionStatusView(
        number: "01", title: "Accessibility".localized,
        description: "Read selection and recognize shortcuts".localized)
    private let fullDiskAccessRow = PermissionStatusView(
        number: "02", title: "Full Disk Access".localized,
        description: "Optional: access protected files".localized, optional: true)
    private let permissionHelpButton = PanelStyle.makeQuietButton(title: "Glance not listed?".localized, target: nil, action: nil)
    private let blockingDot = NSView()
    private let blockingLabel = PanelCenteredTextView()
    private let footnote = PanelCenteredTextView()
    private let continueButton = PanelStyle.makePrimaryButton(title: "Continue".localized, target: nil, action: nil)
    private var permissionCheckGeneration = UUID()

    init() {
        let initial = ScreenManager.shared.contentFrame(for: Self.designSize)
        super.init(contentRect: initial,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Welcome to Glance".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        appearance = PanelStyle.windowAppearance
        backgroundColor = PanelStyle.surface
        contentAspectRatio = Self.designSize
        minSize = NSSize(width: min(512, initial.width), height: min(496, initial.height))
        isReleasedWhenClosed = false
        level = .normal
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
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surface)
        root.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        root.layer?.borderWidth = 1
        root.layer?.cornerRadius = PanelStyle.Radius.window
        root.layer?.masksToBounds = true

        let traffic: [(NSColor, Selector)] = [
            (NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), #selector(closeTapped)),
            (NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), #selector(minimizeTapped)),
            (NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), #selector(zoomTapped))
        ]
        for (color, action) in traffic {
            titlebar.addSubview(TrafficLightButton(color: color, target: self, action: action))
        }
        root.addSubview(titlebar)

        heading.textColor = PanelStyle.textPrimary
        heading.lineBreakMode = .byTruncatingTail
        root.addSubview(heading)
        explanation.textColor = PanelStyle.textSecondary
        explanation.maximumNumberOfLines = 2
        explanation.lineBreakMode = .byWordWrapping
        root.addSubview(explanation)

        accessibilityRow.onOpenSettings = { PermissionManager.shared.openAccessibilitySettings() }
        fullDiskAccessRow.onOpenSettings = { PermissionManager.shared.openFullDiskAccessSettings() }
        [accessibilityRow, fullDiskAccessRow].forEach(root.addSubview)

        permissionHelpButton.target = self
        permissionHelpButton.action = #selector(showPermissionHelp)
        permissionHelpButton.normalBackground = .clear
        permissionHelpButton.hoverBackground = PanelStyle.controlFill
        permissionHelpButton.titleColor = PanelStyle.textTertiary
        permissionHelpButton.layer?.borderWidth = 0
        root.addSubview(permissionHelpButton)

        // Blocking reason: a small shu dot and one sentence, only while Peek can't run.
        blockingDot.wantsLayer = true
        blockingDot.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.failure)
        root.addSubview(blockingDot)
        blockingLabel.string = "Accessibility is still off — Peek won’t work until it’s allowed.".localized
        blockingLabel.textColor = PanelStyle.textSecondary
        blockingLabel.alignment = .left
        root.addSubview(blockingLabel)

        footnote.string = "Permissions stay under your control in macOS System Settings.".localized
        footnote.textColor = PanelStyle.textTertiary
        footnote.alignment = .left
        root.addSubview(footnote)

        continueButton.target = self
        continueButton.action = #selector(continuePressed)
        continueButton.isEnabled = true
        continueButton.keyEquivalent = "\r"
        continueButton.layer?.borderWidth = 0
        root.addSubview(continueButton)
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
        /// Figma top-origin frame → AppKit bottom-origin frame in the scaled window.
        func fromTop(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * sx, y: size.height - (y + h) * sy, width: w * sx, height: h * sy)
        }
        func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        root.layer?.cornerRadius = PanelStyle.Radius.window * scale
        root.layer?.borderWidth = max(1, scale)

        titlebar.frame = fromTop(0, 0, Self.designSize.width, 44)
        for (index, button) in titlebar.subviews.compactMap({ $0 as? TrafficLightButton }).enumerated() {
            button.frame = NSRect(x: CGFloat(20 + index * 20) * sx, y: titlebar.bounds.height - 28 * sy,
                                  width: 12 * sx, height: 12 * sy)
        }

        // Content column: x 64, width 512, starting 76 below the top.
        heading.font = PanelStyle.titleFont(ofSize: 30 * scale)
        heading.frame = fromTop(64, 106, 512, 38)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 21 * scale
        paragraph.maximumLineHeight = 21 * scale
        paragraph.lineBreakMode = .byWordWrapping
        explanation.attributedStringValue = NSAttributedString(
            string: explanation.stringValue,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 13 * scale),
                         .foregroundColor: PanelStyle.textSecondary,
                         .paragraphStyle: paragraph])
        explanation.frame = fromTop(64, 154, 512, 42)

        accessibilityRow.frame = fromTop(64, 232, 512, 69)
        fullDiskAccessRow.frame = fromTop(64, 301, 512, 69)

        let helpFont = PanelStyle.inspectFont(ofSize: 12 * scale)
        permissionHelpButton.titleFont = helpFont
        let helpWidth = textWidth(permissionHelpButton.title, helpFont) / sx + 16
        permissionHelpButton.frame = fromTop(56, 382, helpWidth, 24)
        permissionHelpButton.layer?.cornerRadius = PanelStyle.Radius.control * scale

        blockingDot.frame = fromTop(64, 522, 5, 5)
        blockingDot.layer?.cornerRadius = 2.5 * scale
        blockingLabel.font = PanelStyle.inspectFont(ofSize: 12 * scale)
        blockingLabel.frame = fromTop(77, 517, 499, 15)

        let continueFont = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .medium)
        continueButton.titleFont = continueFont
        let continueWidth = max(89, textWidth(continueButton.title, continueFont) / sx + 32)
        continueButton.frame = fromTop(576 - continueWidth, 548, continueWidth, 32)
        continueButton.layer?.cornerRadius = PanelStyle.Radius.control * scale

        footnote.font = PanelStyle.inspectFont(ofSize: 12 * scale)
        footnote.frame = fromTop(64, 556.5, 576 - continueWidth - 8 - 64, 15)
    }

    private func updatePermissionStatus() {
        let manager = PermissionManager.shared
        let accessibility = manager.isAccessibilityGranted
        accessibilityRow.updateStatus(granted: accessibility)
        // Permissions enable individual features; they never gate leaving setup.
        blockingDot.isHidden = accessibility
        blockingLabel.isHidden = accessibility

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
    private func dismissGuide() {
        Preferences.shared.permissionSetupDismissed = true
        close()
    }

    override func performClose(_ sender: Any?) { dismissGuide() }
    override func cancelOperation(_ sender: Any?) { dismissGuide() }
    @objc private func closeTapped() { dismissGuide() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }
    @objc private func continuePressed() { dismissGuide() }
    @objc private func showPermissionHelp() {
        PermissionManager.shared.showManualSetupHelp(for: self)
    }

    override func close() {
        permissionCheckGeneration = UUID()
        super.close()
        NotificationCenter.default.post(name: Self.didClose, object: nil)
    }
}

/// Transparent drag strip across the top 44 pt; double-click zooms.
private final class OnboardingTitlebar: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) }
        else { window?.performDrag(with: event) }
    }
}

/// Figma `permission` row (512 × 69): mono number, title (+ Optional tag),
/// description, and either a moss "Allowed" check or an Open Settings button.
/// Rows are separated by a bottom hairline; no cards.
final class PermissionStatusView: NSView {
    var onOpenSettings: (() -> Void)?

    private static let designSize = NSSize(width: 512, height: 69)

    private let numberLabel = PanelCenteredTextView()
    private let titleLabel = PanelCenteredTextView()
    private let optionalLabel = PanelCenteredTextView()
    private let detailLabel = PanelCenteredTextView()
    private let allowedIcon = NSImageView()
    private let allowedLabel = PanelCenteredTextView()
    private let statusButton = PanelStyle.makeQuietButton(title: "Open Settings".localized, target: nil, action: nil)
    private let separator = NSView()
    private let isOptional: Bool
    private var granted = false

    init(number: String, title: String, description: String, optional: Bool = false) {
        isOptional = optional
        super.init(frame: .zero)
        numberLabel.string = number
        numberLabel.textColor = PanelStyle.textTertiary
        numberLabel.alignment = .left
        titleLabel.string = title
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.alignment = .left
        optionalLabel.string = "Optional".localized
        optionalLabel.textColor = PanelStyle.textTertiary
        optionalLabel.alignment = .left
        optionalLabel.isHidden = !optional
        detailLabel.string = description
        detailLabel.textColor = PanelStyle.textTertiary
        detailLabel.alignment = .left
        [numberLabel, titleLabel, optionalLabel, detailLabel].forEach(addSubview)

        allowedIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        allowedIcon.imageScaling = .scaleProportionallyDown
        allowedIcon.contentTintColor = PanelStyle.success
        addSubview(allowedIcon)
        allowedLabel.string = "Allowed".localized
        allowedLabel.textColor = PanelStyle.success
        allowedLabel.alignment = .right
        addSubview(allowedLabel)

        // Required permissions use a filled quiet button; optional ones an outlined one.
        statusButton.target = self
        statusButton.action = #selector(statusTapped)
        statusButton.titleColor = PanelStyle.textPrimary
        statusButton.normalBackground = optional ? .clear : PanelStyle.controlFillHi
        statusButton.hoverBackground = optional ? PanelStyle.controlFill : PanelStyle.hoverTinted(PanelStyle.controlFillHi)
        statusButton.layer?.borderWidth = optional ? 1 : 0
        statusButton.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        statusButton.toolTip = "Open Settings".localized
        statusButton.setAccessibilityLabel("\(title), \("Open Settings".localized)")
        addSubview(statusButton)

        separator.wantsLayer = true
        separator.layer?.backgroundColor = PanelStyle.resolvedCG(
            PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line))
        addSubview(separator)
        setAccessibilityElement(false)
        updateStatus(granted: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let sx = bounds.width / Self.designSize.width
        let sy = bounds.height / Self.designSize.height
        let scale = min(sx, sy)
        func fromTop(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * sx, y: bounds.height - (y + h) * sy, width: w * sx, height: h * sy)
        }
        func designWidth(_ text: String, _ font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width) / sx
        }

        numberLabel.font = PanelStyle.monoFont(ofSize: 11 * scale)
        numberLabel.frame = fromTop(0, 27, 24, 14)

        let statusFont = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .medium)
        statusButton.titleFont = statusFont
        let buttonWidth = designWidth(statusButton.title, statusFont) + 32
        statusButton.frame = fromTop(512 - buttonWidth, 18, buttonWidth, 32)
        statusButton.layer?.cornerRadius = PanelStyle.Radius.control * scale

        let allowedFont = PanelStyle.inspectFont(ofSize: 12 * scale)
        allowedLabel.font = allowedFont
        let allowedWidth = designWidth(allowedLabel.string, allowedFont)
        allowedLabel.frame = fromTop(512 - allowedWidth, 26.5, allowedWidth, 15)
        allowedIcon.frame = fromTop(512 - allowedWidth - 22, 26, 16, 16)

        let trailing = granted ? allowedWidth + 22 : buttonWidth
        let textWidth = 512 - 30 - trailing - 16
        let titleFont = PanelStyle.inspectFont(ofSize: 14 * scale)
        titleLabel.font = titleFont
        let titleWidth = min(designWidth(titleLabel.string, titleFont), textWidth)
        titleLabel.frame = fromTop(30, 16, titleWidth, 17)
        let optionalFont = PanelStyle.inspectFont(ofSize: 11 * scale)
        optionalLabel.font = optionalFont
        optionalLabel.frame = fromTop(30 + titleWidth + 8, 18,
                                      max(0, min(designWidth(optionalLabel.string, optionalFont), textWidth - titleWidth - 8)), 13)
        detailLabel.font = PanelStyle.inspectFont(ofSize: 12 * scale)
        detailLabel.frame = fromTop(30, 37, textWidth, 15)

        separator.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(1, scale))
    }

    func updateStatus(granted: Bool) {
        self.granted = granted
        statusButton.isHidden = granted
        allowedIcon.isHidden = !granted
        allowedLabel.isHidden = !granted
        allowedLabel.setAccessibilityLabel("\(titleLabel.string), \("Allowed".localized)")
        needsLayout = true
    }

    @objc private func statusTapped() {
        guard !granted else { return }
        onOpenSettings?()
    }
}
