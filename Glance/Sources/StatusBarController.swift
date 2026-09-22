import AppKit

protocol StatusBarControllerDelegate: AnyObject {
    func openHome()
    func openPreferences()
    func checkAndRequestPermissions()
    func clearImageCache()
    func openHistory()
    func openTasks()
    func openLogin(at point: NSPoint)
}

class StatusBarController: NSObject, NSMenuDelegate {
    weak var delegate: StatusBarControllerDelegate?

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var enableMenuItem: NSMenuItem!
    private var permissionMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var tasksMenuItem: NSMenuItem!
    private var trayPanel: TrayPopoverPanel?

    override init() {
        super.init()
        setupStatusBar()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: .preferencesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(self, selector: #selector(tasksDidChange), name: WidgetTaskManager.didChange, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func preferencesDidChange() {
        enableMenuItem?.state = Preferences.shared.enabled ? .on : .off
        trayPanel?.refreshState()
        updateMenuBarIcon()
    }

    @objc private func languageDidChange() {
        // Drop the cached panel so it rebuilds with the new language on next open.
        trayPanel?.close()
        trayPanel = nil
        updateMenuBarIcon()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Left click opens the Glance-themed panel; right click / control-click
        // falls back to a minimal native menu (Quit etc.).
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateMenuBarIcon()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isRightClick {
            showFallbackMenu()
        } else {
            toggleTrayPanel()
        }
    }

    private func toggleTrayPanel() {
        if let panel = trayPanel, panel.isVisible {
            panel.close()
            return
        }
        let panel = trayPanel ?? TrayPopoverPanel(delegate: self)
        trayPanel = panel
        guard let button = statusItem.button else { return }
        panel.present(below: button)
    }

    /// Minimal right-click safety net so the app is always quittable even if
    /// the panel misbehaves.
    private func showFallbackMenu() {
        let fallback = NSMenu()
        fallback.appearance = NSAppearance(named: .darkAqua)
        let home = NSMenuItem(title: "Open Home".localized, action: #selector(openHome), keyEquivalent: "")
        home.target = self; fallback.addItem(home)
        let prefs = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferences), keyEquivalent: "")
        prefs.target = self; fallback.addItem(prefs)
        fallback.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Glance".localized, action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; fallback.addItem(quit)
        statusItem.menu = fallback
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }
        let enabled = Preferences.shared.enabled
        let symbolName = enabled ? "eye.fill" : "eye.slash"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Glance")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.attributedTitle = NSAttributedString(string: "")
        button.image = image
        button.imagePosition = .imageOnly
        button.contentTintColor = enabled ? PanelStyle.warmCue : PanelStyle.textSecondary
    }

    private func createMenu() -> NSMenu {
        menu = NSMenu()
        menu.delegate = self
        // Keep the menu on the app's darkroom chrome even when the system is
        // in light mode: dark frosted material instead of a light menu.
        menu.appearance = NSAppearance(named: .darkAqua)

        let homeItem = NSMenuItem(title: "Open Home".localized, action: #selector(openHome), keyEquivalent: "n")
        homeItem.target = self
        menu.addItem(homeItem)

        let preferencesItem = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        enableMenuItem = NSMenuItem(title: "Enable Preview".localized, action: #selector(toggleEnable), keyEquivalent: "")
        enableMenuItem.target = self
        enableMenuItem.state = Preferences.shared.enabled ? .on : .off
        menu.addItem(enableMenuItem)

        menu.addItem(NSMenuItem.separator())

        permissionMenuItem = NSMenuItem(title: "Permissions...".localized, action: #selector(openPermissions), keyEquivalent: "")
        permissionMenuItem.target = self
        menu.addItem(permissionMenuItem)

        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem(title: "History".localized, action: #selector(openHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        tasksMenuItem = NSMenuItem(title: tasksTitle, action: #selector(openTasks), keyEquivalent: "")
        tasksMenuItem.target = self
        menu.addItem(tasksMenuItem)

        let clearCacheItem = NSMenuItem(title: "Clear Cache".localized, action: #selector(clearCache), keyEquivalent: "")
        clearCacheItem.target = self
        menu.addItem(clearCacheItem)

        loginMenuItem = NSMenuItem(title: "Login".localized, action: #selector(openLogin), keyEquivalent: "")
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About Glance".localized, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Glance".localized, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openHome() {
        delegate?.openHome()
    }

    @objc private func openPreferences() {
        delegate?.openPreferences()
    }

    @objc private func toggleEnable() {
        Preferences.shared.enabled.toggle()
        enableMenuItem.state = Preferences.shared.enabled ? .on : .off
        updateMenuBarIcon()
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func openPermissions() {
        delegate?.checkAndRequestPermissions()
    }

    @objc private func openHistory() {
        delegate?.openHistory()
    }

    @objc private func openTasks() { delegate?.openTasks() }
    @objc private func tasksDidChange() {
        tasksMenuItem?.title = tasksTitle
        trayPanel?.refreshState()
    }
    private var tasksTitle: String { let count = WidgetTaskManager.shared.activeCount; return count > 0 ? "\("Tasks".localized) (\(count))" : "Tasks".localized }

    @objc private func clearCache() {
        delegate?.clearImageCache()
    }

    @objc private func openLogin() {
        delegate?.openLogin(at: loginPanelAnchorPoint())
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Glance".localized
        alert.informativeText = "Version 1.0\n\nHold Cmd+Shift and hover over image URLs or file paths to see instant previews.".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK".localized)
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func loginPanelAnchorPoint() -> NSPoint {
        if let button = statusItem.button,
           let window = button.window {
            let windowFrame = button.convert(button.bounds, to: nil)
            let screenFrame = window.convertToScreen(windowFrame)
            return NSPoint(x: screenFrame.midX, y: screenFrame.minY)
        }
        return NSEvent.mouseLocation
    }

    func menuWillOpen(_ menu: NSMenu) {
        let permissionManager = PermissionManager.shared
        let inputMonitoringGranted = permissionManager.isInputMonitoringGranted
        let accessibilityGranted = permissionManager.isAccessibilityGranted

        if let permissionMenuItem = permissionMenuItem {
            permissionMenuItem.title = (inputMonitoringGranted && accessibilityGranted)
                ? "Permissions ✅".localized : "Permissions ⚠️".localized
        }
        loginMenuItem?.title = AuthManager.shared.isSignedIn ? "Account".localized : "Login".localized
    }

}

// MARK: - TrayPopoverDelegate

extension StatusBarController: TrayPopoverDelegate {
    func trayOpenHome() { delegate?.openHome() }
    func trayOpenTasks() { delegate?.openTasks() }
    func trayOpenHistory() { delegate?.openHistory() }
    func trayOpenPreferences() { delegate?.openPreferences() }
    func trayOpenPermissions() { delegate?.checkAndRequestPermissions() }
    func trayOpenAccount() { delegate?.openLogin(at: loginPanelAnchorPoint()) }
    func trayTogglePreview() { toggleEnable() }
    func trayShowAbout() { showAbout() }
    func trayQuit() { quitApp() }
}
