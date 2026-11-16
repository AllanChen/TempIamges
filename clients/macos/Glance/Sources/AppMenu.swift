import AppKit
import UniformTypeIdentifiers

/// The app's main menu. Glance is a regular Dock app that Finder hands images
/// and videos to, so File ▸ Open, the standard Edit commands and Window
/// management have to exist even when no Glance window is frontmost. Windows
/// that handle a key equivalent themselves (Home, Image/Video Inspect) still
/// get it first.
extension AppDelegate {
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // Glance
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Glance")
        appMenu.addItem(menuItem("About Glance", #selector(showAboutFromMenu(_:)), target: self))
        #if !MAS
        appMenu.addItem(menuItem("Check for Updates…", #selector(AppUpdater.checkForUpdates(_:)), target: AppUpdater.shared))
        #endif
        appMenu.addItem(menuItem("Buy Glance Pro…", #selector(openProFromMenu(_:)), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Preferences...", #selector(openPreferencesFromMenu(_:)), key: ",", target: self))
        #if MAS
        appMenu.addItem(menuItem("Grant Folder Access…", #selector(grantFolderAccessFromMenu(_:)), target: self))
        #endif
        appMenu.addItem(menuItem("Team account", #selector(AccountActions.manageTeam(_:)), target: AccountActions.shared))
        appMenu.addItem(menuItem("Delete account", #selector(AccountActions.deleteAccount(_:)), target: AccountActions.shared))
        appMenu.addItem(menuItem("Set as Default Viewer…", #selector(setAsDefaultViewer(_:)), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Hide Glance", #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(menuItem("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h",
                                 modifiers: [.command, .option]))
        appMenu.addItem(menuItem("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Quit Glance", #selector(NSApplication.terminate(_:)), key: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File".localized)
        fileMenu.addItem(menuItem("Open…", #selector(openFilesFromMenu(_:)), key: "o", target: self))
        fileMenu.addItem(menuItem("Open Folder…", #selector(openFolderFromMenu(_:)), key: "o",
                                  modifiers: [.command, .shift], target: self))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("Close Window", #selector(NSWindow.performClose(_:)), key: "w"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit: standard responder-chain commands so text fields (search,
        // hotkey, Base64 input) behave like in any Mac app.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit".localized)
        editMenu.addItem(menuItem("Undo", Selector(("undo:")), key: "z"))
        editMenu.addItem(menuItem("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem("Cut", #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(menuItem("Copy", #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(menuItem("Paste", #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(menuItem("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // Window
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window".localized)
        windowMenu.addItem(menuItem("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(menuItem("Zoom", #selector(NSWindow.performZoom(_:))))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help".localized)
        helpMenu.addItem(menuItem("Report a Bug…", #selector(reportBugFromMenu(_:)), target: self))
        helpMenu.addItem(menuItem("Reveal Log", #selector(revealLogFromMenu(_:)), target: self))
        helpMenu.addItem(menuItem("Export Diagnostics…", #selector(exportDiagnosticsFromMenu(_:)), target: self))
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "",
                          modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title.localized, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        item.target = target
        return item
    }

    @objc private func showAboutFromMenu(_ sender: Any?) { statusBarController?.showAbout() }
    @objc private func reportBugFromMenu(_ sender: Any?) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@glancepreview.com"
        components.queryItems = [URLQueryItem(name: "subject", value: "Glance bug report"),
                                URLQueryItem(name: "body", value: SupportDiagnostics.reportTemplate)]
        if let url = components.url, NSWorkspace.shared.open(url) { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SupportDiagnostics.reportTemplate, forType: .string)
        let alert = NSAlert()
        alert.messageText = "Bug report copied".localized
        alert.informativeText = "Send the copied report to support@glancepreview.com. Logs are not attached or sent automatically.".localized
        alert.runModal()
    }
    @objc private func revealLogFromMenu(_ sender: Any?) { Logger.revealLogFile() }
    @objc private func exportDiagnosticsFromMenu(_ sender: Any?) {
        let confirm = NSAlert()
        confirm.messageText = "Export diagnostics for review?".localized
        confirm.informativeText = "The file contains app and system versions, permission status and a redacted recent log. Review it before emailing support@glancepreview.com. Nothing is uploaded automatically. Do not post logs, email addresses, full order details or redemption codes publicly.".localized
        confirm.addButton(withTitle: "Export".localized)
        confirm.addButton(withTitle: "Cancel".localized)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Glance-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let header = SupportDiagnostics.reportTemplate + "\nAccessibility: \(PermissionManager.shared.isAccessibilityGranted)\nInput Monitoring: \(PermissionManager.shared.isInputMonitoringGranted)\n"
            Logger.exportDiagnostics(to: url, header: header) { error in
                if let error {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
    @objc private func openPreferencesFromMenu(_ sender: Any?) { openPreferences() }
    #if MAS
    @objc private func grantFolderAccessFromMenu(_ sender: Any?) { FolderAccess.shared.requestAccess() }
    #endif
    @objc private func openProFromMenu(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        BillingCoordinator.shared.showProEntry(over: NSApp.keyWindow ?? NSApp.mainWindow)
    }

    @objc private func openFilesFromMenu(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.openMediaFromHome(panel.urls)
        }
    }

    @objc private func openFolderFromMenu(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.urls.first else { return }
            self?.openFolder(folder)
        }
    }

    /// Makes Glance the app Finder uses for images and videos.
    @objc func setAsDefaultViewer(_ sender: Any?) {
        let confirm = NSAlert()
        confirm.messageText = "Set Glance as the default viewer?".localized
        confirm.informativeText = "Images and videos you open from Finder will open in Glance.".localized
        confirm.addButton(withTitle: "Set as Default".localized)
        confirm.addButton(withTitle: "Cancel".localized)
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        applyDefaultViewer()
    }

    /// Right after the first "Open With ▸ Glance" from Finder is the moment a
    /// user is most likely to want this; the menu item alone is rarely found.
    func offerDefaultViewerIfNeeded() {
        let prefs = Preferences.shared
        guard !prefs.hasOfferedDefaultViewer else { return }
        prefs.hasOfferedDefaultViewer = true
        let current = NSWorkspace.shared.urlForApplication(toOpen: UTType.image)?.standardizedFileURL
        guard current != Bundle.main.bundleURL.standardizedFileURL else { return }
        // Let the just-opened Inspect window settle on screen first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            let alert = NSAlert()
            alert.messageText = "Make Glance your default viewer?".localized
            alert.informativeText = "Images and videos you open from Finder will open in Glance. You can change this anytime from the Glance menu.".localized
            alert.addButton(withTitle: "Set as Default".localized)
            alert.addButton(withTitle: "Not Now".localized)
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { self?.applyDefaultViewer() }
        }
    }

    private func applyDefaultViewer() {
        let types: [UTType] = [.image, .movie, UTType("org.webmproject.webm")].compactMap { $0 }
        let group = DispatchGroup()
        var firstError: Error?
        for type in types {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
                DispatchQueue.main.async {
                    if firstError == nil { firstError = error }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            let result = NSAlert()
            if let firstError {
                result.messageText = "Could not set the default viewer".localized
                result.informativeText = firstError.localizedDescription
            } else {
                result.messageText = "Glance is now the default viewer".localized
            }
            result.addButton(withTitle: "OK".localized)
            result.runModal()
        }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openProFromMenu(_:)) {
            menuItem.title = (BillingManager.shared.shouldManagePro ? "Manage Pro…" : "Buy Glance Pro…").localized
        }
        return true
    }
}
