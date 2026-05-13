import AppKit

protocol StatusBarControllerDelegate: AnyObject {
    func openPreferences()
    func checkAndRequestPermissions()
    func clearImageCache()
    func openHistory()
}

class StatusBarController: NSObject, NSMenuDelegate {
    weak var delegate: StatusBarControllerDelegate?

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var enableMenuItem: NSMenuItem!
    private var permissionMenuItem: NSMenuItem!

    override init() {
        super.init()
        setupStatusBar()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = createMenu()

        updateMenuBarIcon()
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }

        if #available(macOS 11.0, *) {
            let symbolName = Preferences.shared.enabled ? "eye" : "eye.slash"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ImageHoverPreview")
        } else {
            button.title = Preferences.shared.enabled ? "👁" : "🚫"
        }
        button.image?.isTemplate = true
    }

    private func createMenu() -> NSMenu {
        menu = NSMenu()
        menu.delegate = self

        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        enableMenuItem = NSMenuItem(title: "Enable Preview", action: #selector(toggleEnable), keyEquivalent: "")
        enableMenuItem.target = self
        enableMenuItem.state = Preferences.shared.enabled ? .on : .off
        menu.addItem(enableMenuItem)

        menu.addItem(NSMenuItem.separator())

        permissionMenuItem = NSMenuItem(title: "Permissions...", action: #selector(openPermissions), keyEquivalent: "")
        permissionMenuItem.target = self
        menu.addItem(permissionMenuItem)

        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        let clearCacheItem = NSMenuItem(title: "Clear Cache", action: #selector(clearCache), keyEquivalent: "")
        clearCacheItem.target = self
        menu.addItem(clearCacheItem)

        // Theme submenu — system / light / dark. Selection is reflected as
        // a checkmark in `menuWillOpen`.
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeSubmenu = NSMenu(title: "Theme")
        for theme in Preferences.Theme.allCases {
            let item = NSMenuItem(title: theme.displayName,
                                   action: #selector(selectTheme(_:)),
                                   keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            themeSubmenu.addItem(item)
        }
        themeItem.submenu = themeSubmenu
        menu.addItem(themeItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About ImageHoverPreview", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit ImageHoverPreview", action: #selector(quitApp), keyEquivalent: "q")
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

    @objc private func clearCache() {
        delegate?.clearImageCache()
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = Preferences.Theme(rawValue: raw) else { return }
        Preferences.shared.theme = theme
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "ImageHoverPreview"
        alert.informativeText = "Version 1.0\n\nHold Cmd+Shift and hover over image URLs or file paths to see instant previews."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        let permissionManager = PermissionManager.shared
        let inputMonitoringGranted = permissionManager.isInputMonitoringGranted
        let accessibilityGranted = permissionManager.isAccessibilityGranted

        if inputMonitoringGranted && accessibilityGranted {
            permissionMenuItem.title = "Permissions ✅"
        } else {
            var missing: [String] = []
            if !inputMonitoringGranted { missing.append("Input Monitoring") }
            if !accessibilityGranted { missing.append("Accessibility") }
            permissionMenuItem.title = "Permissions ⚠️"
        }

        // Reflect the active theme in the submenu.
        let active = Preferences.shared.theme.rawValue
        for item in self.menu.items {
            guard let submenu = item.submenu, submenu.title == "Theme" else { continue }
            for sub in submenu.items {
                sub.state = ((sub.representedObject as? String) == active) ? .on : .off
            }
        }
    }
}
