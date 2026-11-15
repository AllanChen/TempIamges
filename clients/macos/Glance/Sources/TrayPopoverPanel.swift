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

/// The menu bar popover (Figma `06 · Menu Bar Popover`, states in `49 · Menu
/// Bar / States`): one calm translucent ink/2 surface replacing the native
/// NSMenu. Borderless NSPanel anchored under the status-bar icon; closes when
/// it loses focus.
final class TrayPopoverPanel: NSPanel, NSWindowDelegate {
    weak var trayDelegate: TrayPopoverDelegate?

    private static let panelSize = NSSize(width: 288, height: 341)

    private let root = NSView()
    private let surface = NSView()
    private let brandLabel = PanelCenteredTextView()
    private let peekDot = NSView()
    private let previewSubLabel = PanelCenteredTextView()
    private let previewToggle = TrayToggle()
    private let tasksRow: TrayRow
    private let permissionsRow: TrayRow
    private let accountRow: TrayRow

    init(delegate: TrayPopoverDelegate) {
        self.trayDelegate = delegate
        self.tasksRow = TrayRow(icon: "list.bullet", title: "Tasks".localized)
        self.permissionsRow = TrayRow(icon: "shield", title: "Permissions".localized)
        self.accountRow = TrayRow(icon: "person", title: "Account".localized)
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
        appearance = PanelStyle.windowAppearance
        buildUI()
    }

    // MARK: Build

    /// Figma frame in top-origin popover coordinates → AppKit frame.
    private func fromTop(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x, y: Self.panelSize.height - y - h, width: w, height: h)
    }

    private func buildUI() {
        let bounds = NSRect(origin: .zero, size: Self.panelSize)
        root.frame = bounds
        contentView = root

        let blur = NSVisualEffectView(frame: bounds)
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = PanelStyle.vibrantAppearance
        blur.maskImage = PanelStyle.roundedMask(radius: PanelStyle.Radius.window)
        root.addSubview(blur)

        surface.frame = bounds
        surface.wantsLayer = true
        surface.layer?.backgroundColor = PanelStyle.resolvedCG(
            PanelStyle.themed(PanelStyle.Sumi.ink2, PanelStyle.Washi.ink2).withAlphaComponent(0.94))
        surface.layer?.cornerRadius = PanelStyle.Radius.window
        surface.layer?.masksToBounds = true
        surface.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        surface.layer?.borderWidth = 1
        root.addSubview(surface)

        // Header: wordmark, Peek state, Peek toggle.
        brandLabel.string = "Glance".localized
        brandLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        brandLabel.textColor = PanelStyle.textPrimary
        brandLabel.alignment = .left
        brandLabel.frame = fromTop(17, 17, 200, 16)
        surface.addSubview(brandLabel)
        peekDot.wantsLayer = true
        peekDot.layer?.cornerRadius = 2.5
        peekDot.frame = fromTop(17, 40, 5, 5)
        surface.addSubview(peekDot)
        previewSubLabel.font = PanelStyle.inspectFont(ofSize: 11)
        previewSubLabel.textColor = PanelStyle.textTertiary
        previewSubLabel.alignment = .left
        previewSubLabel.frame = fromTop(28, 36, 190, 13)
        surface.addSubview(previewSubLabel)
        previewToggle.frame = fromTop(241, 24, 30, 18)
        previewToggle.onToggle = { [weak self] in self?.trayDelegate?.trayTogglePreview() }
        surface.addSubview(previewToggle)

        addDivider(top: 61)

        let home = TrayRow(icon: "photo", title: "Open Glance Home".localized)
        placeRow(home, top: 72) { [weak self] in self?.fire { $0.trayOpenHome() } }
        placeRow(tasksRow, top: 102) { [weak self] in self?.fire { $0.trayOpenTasks() } }
        let history = TrayRow(icon: "clock.arrow.circlepath", title: "Preview History".localized)
        placeRow(history, top: 132) { [weak self] in self?.fire { $0.trayOpenHistory() } }
        let prefs = TrayRow(icon: "slider.horizontal.3", title: "Preferences...".localized, shortcut: "⌘,")
        placeRow(prefs, top: 162) { [weak self] in self?.fire { $0.trayOpenPreferences() } }

        addDivider(top: 192)

        placeRow(permissionsRow, top: 203) { [weak self] in self?.fire { $0.trayOpenPermissions() } }
        placeRow(accountRow, top: 233) { [weak self] in self?.fire { $0.trayOpenAccount() } }

        addDivider(top: 263)

        let about = TrayRow(icon: nil, title: "About Glance".localized)
        placeRow(about, top: 274) { [weak self] in self?.fire { $0.trayShowAbout() } }
        let quit = TrayRow(icon: nil, title: "Quit".localized)
        placeRow(quit, top: 304) { [weak self] in self?.fire { $0.trayQuit() } }
    }

    private func placeRow(_ row: TrayRow, top: CGFloat, action: @escaping () -> Void) {
        row.frame = fromTop(7, top, Self.panelSize.width - 14, 30)
        row.onClick = action
        surface.addSubview(row)
    }

    /// Figma divider: an 11 pt band holding a 1 pt line inset 10 pt inside the rows.
    private func addDivider(top: CGFloat) {
        let line = NSView(frame: fromTop(17, top + 5, Self.panelSize.width - 34, 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = PanelStyle.resolvedCG(
            PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line))
        surface.addSubview(line)
    }

    /// Run a delegate action then close the panel (menu-like behavior).
    private func fire(_ block: (TrayPopoverDelegate) -> Void) {
        if let d = trayDelegate { block(d) }
        close()
    }

    // MARK: Show / state

    func refreshState() {
        let on = Preferences.shared.peekEnabled
        previewToggle.setOn(on)
        previewSubLabel.string = on ? "Peek is on".localized : "Peek is off".localized
        peekDot.layer?.backgroundColor = PanelStyle.resolvedCG(
            on ? PanelStyle.success : PanelStyle.themed(PanelStyle.Sumi.text4, PanelStyle.Washi.text4))

        let taskCount = WidgetTaskManager.shared.activeCount
        tasksRow.setTrailing(taskCount > 0 ? String(format: "%d running".localized, taskCount) : nil,
                             color: PanelStyle.info)

        let pm = PermissionManager.shared
        let granted = pm.canUsePeek
        permissionsRow.setTrailing(granted ? "All set".localized : "Action needed".localized,
                                   color: granted ? PanelStyle.success : PanelStyle.failure)

        let signedIn = AuthManager.shared.isSignedIn
        accountRow.setTitle(BillingManager.shared.trialBadge ?? (BillingManager.shared.hasPro ? "Glance Pro" : "Account".localized))
        let credits = AuthManager.shared.session?.user.credits.map { String(format: "%d credits".localized, $0) }
        accountRow.setTrailing(signedIn ? credits : "Sign in".localized, color: PanelStyle.textTertiary)
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
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override var canBecomeKey: Bool { true }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

// MARK: - Row / control views

/// Figma `item / …`: 274 × 30, 16 pt line icon in text/2 at x 10, label at x 36,
/// trailing status or shortcut right-aligned to x 264. Hover fills ink/4.
private final class TrayRow: NSView {
    var onClick: (() -> Void)?
    private let iconView = NSImageView()
    private let titleLabel = PanelCenteredTextView()
    private let trailingLabel = PanelCenteredTextView()
    private let hasIcon: Bool
    private let hasShortcut: Bool

    init(icon: String?, title: String, shortcut: String? = nil) {
        hasIcon = icon != nil
        hasShortcut = shortcut != nil
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        if let icon {
            iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            iconView.imageScaling = .scaleProportionallyDown
            iconView.contentTintColor = PanelStyle.textSecondary
            addSubview(iconView)
        }
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13)
        titleLabel.textColor = hasIcon ? PanelStyle.textPrimary : PanelStyle.textSecondary
        titleLabel.alignment = .left
        titleLabel.string = title
        addSubview(titleLabel)
        trailingLabel.font = hasShortcut ? PanelStyle.monoFont(ofSize: 11) : PanelStyle.inspectFont(ofSize: 12)
        trailingLabel.textColor = PanelStyle.textTertiary
        trailingLabel.alignment = .right
        trailingLabel.string = shortcut ?? ""
        addSubview(trailingLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTrailing(_ text: String?, color: NSColor) {
        trailingLabel.string = text ?? ""
        trailingLabel.textColor = color
    }
    func setTitle(_ text: String) {
        titleLabel.string = text
        setAccessibilityLabel(text)
    }

    override func layout() {
        super.layout()
        // Rows are 30 tall; Figma y values are converted from the row's top edge.
        iconView.frame = NSRect(x: 10, y: bounds.height - 23, width: 16, height: 16)
        let titleX: CGFloat = hasIcon ? 36 : 10
        titleLabel.frame = NSRect(x: titleX, y: bounds.height - 23, width: bounds.width - titleX - 120, height: 16)
        trailingLabel.frame = hasShortcut
            ? NSRect(x: bounds.width - 10 - 40, y: bounds.height - 22, width: 40, height: 14)
            : NSRect(x: bounds.width - 10 - 110, y: bounds.height - 22.5, width: 110, height: 15)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.surfaceElevated)
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

/// Figma `Toggle`, 30 × 18: text/1 track with an ink knob when on, ink/4 track
/// with a text/3 knob when off.
private final class TrayToggle: NSView {
    var onToggle: (() -> Void)?
    private let knob = NSView()
    private var isOn = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        knob.wantsLayer = true
        addSubview(knob)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("Peek".localized)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setOn(_ on: Bool) {
        isOn = on
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = PanelStyle.resolvedCG(on ? PanelStyle.accent : PanelStyle.surfaceElevated)
        let side = bounds.height - 4
        knob.frame = NSRect(x: on ? bounds.width - side - 2 : 2, y: 2, width: side, height: side)
        knob.layer?.cornerRadius = side / 2
        knob.layer?.backgroundColor = PanelStyle.resolvedCG(on ? PanelStyle.accentInk : PanelStyle.textTertiary)
        setAccessibilityValue(on)
    }
    override func layout() { super.layout(); setOn(isOn) }
    override func mouseDown(with event: NSEvent) { onToggle?() }
    override func accessibilityPerformPress() -> Bool { onToggle?(); return true }
}
