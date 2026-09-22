import AppKit

/// Actions the tray popover can trigger. The controller (StatusBarController)
/// implements these; most forward to AppDelegate.
protocol TrayPopoverDelegate: AnyObject {
    func trayOpenHome()
    func trayOpenTasks()
    func trayOpenHistory()
    func trayOpenPreferences()
    func trayOpenPermissions()
    func trayOpenAccount()
    func trayTogglePreview()
    func trayShowAbout()
    func trayQuit()
}

/// A frosted-dark tray panel that replaces the native gray NSMenu, matching the
/// Figma "Tray Popover / Clean Editable" frame. Borderless NSPanel anchored
/// under the status-bar icon; closes when it loses focus.
final class TrayPopoverPanel: NSPanel, NSWindowDelegate {
    weak var trayDelegate: TrayPopoverDelegate?

    private static let panelSize = NSSize(width: 300, height: 452)

    private let root = NSView()
    private let previewSubLabel = NSTextField(labelWithString: "")
    private let previewToggle = TrayToggle()
    private var rows: [TrayRow] = []
    private let tasksRow: TrayRow
    private let permissionsRow: TrayRow
    private let accountRow: TrayRow

    init(delegate: TrayPopoverDelegate) {
        self.trayDelegate = delegate
        self.tasksRow = TrayRow(icon: "checklist", title: "Tasks".localized)
        self.permissionsRow = TrayRow(icon: "checkmark.shield", title: "Permissions".localized)
        self.accountRow = TrayRow(icon: "person.crop.circle", title: "Account".localized)
        super.init(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.delegate = self
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        buildUI()
    }

    // MARK: Build

    private func buildUI() {
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true
        root.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        root.layer?.borderWidth = 1
        contentView = root

        let W = Self.panelSize.width

        // Header: brand mark + preview toggle
        let mark = NSView(frame: NSRect(x: 16, y: Self.panelSize.height - 50, width: 34, height: 34))
        mark.wantsLayer = true
        mark.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accentSubtleFill)
        mark.layer?.cornerRadius = 9
        root.addSubview(mark)
        let glyph = NSImageView(frame: NSRect(x: 8, y: 8, width: 18, height: 18))
        glyph.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)
        glyph.contentTintColor = PanelStyle.accent
        mark.addSubview(glyph)

        let brand = makeLabel("Glance".localized, size: 15, weight: .semibold, color: PanelStyle.textPrimary)
        brand.frame = NSRect(x: 60, y: Self.panelSize.height - 34, width: 150, height: 20)
        root.addSubview(brand)
        previewSubLabel.font = PanelStyle.inspectFont(ofSize: 10, weight: .medium)
        previewSubLabel.frame = NSRect(x: 60, y: Self.panelSize.height - 50, width: 170, height: 14)
        previewSubLabel.isBordered = false
        previewSubLabel.isEditable = false
        previewSubLabel.backgroundColor = .clear
        root.addSubview(previewSubLabel)

        previewToggle.frame = NSRect(x: W - 50, y: Self.panelSize.height - 43, width: 38, height: 21)
        previewToggle.onToggle = { [weak self] in self?.trayDelegate?.trayTogglePreview() }
        root.addSubview(previewToggle)

        addHairline(y: Self.panelSize.height - 66)

        // Primary: Open Home
        let home = TrayPrimaryButton(title: "Open Glance Home".localized, symbol: "house.fill")
        home.frame = NSRect(x: 12, y: Self.panelSize.height - 124, width: W - 24, height: 44)
        home.onClick = { [weak self] in self?.fire { $0.trayOpenHome() } }
        root.addSubview(home)

        // Navigation rows
        var y = Self.panelSize.height - 138 - 40
        placeRow(tasksRow, y: y) { [weak self] in self?.fire { $0.trayOpenTasks() } }; y -= 44
        let history = TrayRow(icon: "clock.arrow.circlepath", title: "Preview History".localized)
        placeRow(history, y: y) { [weak self] in self?.fire { $0.trayOpenHistory() } }; y -= 44
        let prefs = TrayRow(icon: "gearshape", title: "Preferences".localized, trailing: "⌘,")
        placeRow(prefs, y: y) { [weak self] in self?.fire { $0.trayOpenPreferences() } }; y -= 12

        addHairline(y: y); y -= 44

        // Status rows
        placeRow(permissionsRow, y: y) { [weak self] in self?.fire { $0.trayOpenPermissions() } }; y -= 44
        placeRow(accountRow, y: y) { [weak self] in self?.fire { $0.trayOpenAccount() } }; y -= 12

        addHairline(y: y); y -= 34

        // Footer: About / Quit
        let about = TrayTextButton(title: "About Glance".localized, align: .left)
        about.frame = NSRect(x: 24, y: y, width: 140, height: 18)
        about.onClick = { [weak self] in self?.fire { $0.trayShowAbout() } }
        root.addSubview(about)
        let quit = TrayTextButton(title: "Quit".localized, align: .right)
        quit.frame = NSRect(x: W - 100 - 24, y: y, width: 100, height: 18)
        quit.onClick = { [weak self] in self?.fire { $0.trayQuit() } }
        root.addSubview(quit)
    }

    private func placeRow(_ row: TrayRow, y: CGFloat, action: @escaping () -> Void) {
        row.frame = NSRect(x: 12, y: y, width: Self.panelSize.width - 24, height: 40)
        row.onClick = action
        root.addSubview(row)
        rows.append(row)
    }

    private func addHairline(y: CGFloat) {
        let line = NSView(frame: NSRect(x: 12, y: y, width: Self.panelSize.width - 24, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        root.addSubview(line)
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    /// Run a delegate action then close the panel (menu-like behavior).
    private func fire(_ block: (TrayPopoverDelegate) -> Void) {
        if let d = trayDelegate { block(d) }
        close()
    }

    // MARK: Show / state

    func refreshState() {
        let on = Preferences.shared.enabled
        previewToggle.setOn(on)
        previewSubLabel.stringValue = on ? "Preview is on".localized : "Preview is off".localized
        previewSubLabel.textColor = on ? PanelStyle.success : PanelStyle.textTertiary

        let taskCount = WidgetTaskManager.shared.activeCount
        tasksRow.setBadge(taskCount > 0 ? "\(taskCount)" : nil)

        let pm = PermissionManager.shared
        let granted = pm.isInputMonitoringGranted && pm.isAccessibilityGranted
        permissionsRow.setTrailing(granted ? "All set".localized : "Action needed".localized,
                                   color: granted ? PanelStyle.success : PanelStyle.danger)

        let signedIn = AuthManager.shared.isSignedIn
        accountRow.setTitle(signedIn ? "Account".localized : "Sign in".localized)
        accountRow.setTrailing(signedIn ? "Signed in".localized : nil, color: PanelStyle.textTertiary)
    }

    /// Show the panel anchored under the status-bar button; close on outside click.
    func present(below button: NSStatusBarButton) {
        refreshState()
        guard let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let x = screenRect.midX - Self.panelSize.width / 2
        let y = screenRect.minY - Self.panelSize.height - 6
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override var canBecomeKey: Bool { true }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

// MARK: - Row / control views

private final class TrayRow: NSView {
    var onClick: (() -> Void)?
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let trailingLabel = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private var hovering = false

    init(icon: String, title: String, trailing: String? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.contentTintColor = PanelStyle.textSecondary
        addSubview(iconView)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.isBordered = false; titleLabel.isEditable = false; titleLabel.backgroundColor = .clear
        titleLabel.stringValue = title
        addSubview(titleLabel)
        trailingLabel.font = PanelStyle.inspectFont(ofSize: 11)
        trailingLabel.textColor = PanelStyle.textTertiary
        trailingLabel.alignment = .right
        trailingLabel.isBordered = false; trailingLabel.isEditable = false; trailingLabel.backgroundColor = .clear
        trailingLabel.stringValue = trailing ?? ""
        addSubview(trailingLabel)
        badge.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        badge.textColor = PanelStyle.accentInk
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accent)
        badge.layer?.cornerRadius = 9
        badge.isBordered = false; badge.isEditable = false
        badge.isHidden = true
        addSubview(badge)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setBadge(_ text: String?) {
        badge.isHidden = text == nil
        badge.stringValue = text ?? ""
        needsLayout = true
    }
    func setTrailing(_ text: String?, color: NSColor) {
        trailingLabel.stringValue = text ?? ""
        trailingLabel.textColor = color
    }
    func setTitle(_ text: String) { titleLabel.stringValue = text }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 12, y: (bounds.height - 18) / 2, width: 18, height: 18)
        titleLabel.frame = NSRect(x: 42, y: (bounds.height - 16) / 2, width: bounds.width - 140, height: 16)
        trailingLabel.frame = NSRect(x: bounds.width - 126, y: (bounds.height - 14) / 2, width: 114, height: 14)
        if !badge.isHidden {
            badge.frame = NSRect(x: bounds.width - 44, y: (bounds.height - 20) / 2, width: 32, height: 20)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.controlFill)
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        layer?.backgroundColor = .clear
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

private final class TrayPrimaryButton: NSView {
    var onClick: (() -> Void)?
    init(title: String, symbol: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accent)
        layer?.cornerRadius = 10
        let icon = NSImageView(frame: NSRect(x: 16, y: 13, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = PanelStyle.accentInk
        addSubview(icon)
        let label = NSTextField(labelWithString: title)
        label.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold)
        label.textColor = PanelStyle.accentInk
        label.frame = NSRect(x: 44, y: 14, width: 200, height: 16)
        label.isBordered = false; label.isEditable = false; label.backgroundColor = .clear
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

private final class TrayTextButton: NSView {
    var onClick: (() -> Void)?
    init(title: String, align: NSTextAlignment) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: title)
        label.font = PanelStyle.inspectFont(ofSize: 12)
        label.textColor = PanelStyle.textTertiary
        label.alignment = align
        label.isBordered = false; label.isEditable = false; label.backgroundColor = .clear
        label.frame = NSRect(x: 0, y: 0, width: 140, height: 18)
        label.autoresizingMask = [.width]
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

private final class TrayToggle: NSView {
    var onToggle: (() -> Void)?
    private let knob = NSView()
    private var isOn = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10.5
        knob.wantsLayer = true
        knob.layer?.cornerRadius = 8.5
        addSubview(knob)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setOn(_ on: Bool) {
        isOn = on
        layer?.backgroundColor = PanelStyle.resolvedCG(on ? PanelStyle.accent : PanelStyle.controlFill)
        let knobX: CGFloat = on ? bounds.width - 19 : 2
        knob.frame = NSRect(x: knobX, y: 2, width: 17, height: 17)
        knob.layer?.backgroundColor = PanelStyle.resolvedCG(on ? PanelStyle.accentInk : PanelStyle.textSecondary)
    }
    override func layout() { super.layout(); setOn(isOn) }
    override func mouseDown(with event: NSEvent) { onToggle?() }
}
