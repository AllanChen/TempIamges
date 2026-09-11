import AppKit

protocol StatusBarControllerDelegate: AnyObject {
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
        updateMenuBarIcon()
    }

    @objc private func languageDidChange() {
        statusItem.menu = createMenu()
        updateMenuBarIcon()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = createMenu()

        updateMenuBarIcon()
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
    @objc private func tasksDidChange() { tasksMenuItem?.title = tasksTitle }
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

        if inputMonitoringGranted && accessibilityGranted {
            permissionMenuItem.title = "Permissions ✅".localized
        } else {
            var missing: [String] = []
            if !inputMonitoringGranted { missing.append("Input Monitoring") }
            if !accessibilityGranted { missing.append("Accessibility") }
            permissionMenuItem.title = "Permissions ⚠️".localized
        }

        loginMenuItem.title = AuthManager.shared.isSignedIn ? "Account".localized : "Login".localized
    }

}
