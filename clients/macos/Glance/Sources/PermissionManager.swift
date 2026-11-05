import AppKit
import ApplicationServices
import IOKit.hidsystem

class PermissionManager: NSObject {
    static let shared = PermissionManager()
    
    var isInputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
    
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// The active event tap and selection reader need Accessibility, which
    /// already includes event listening. A separate HID grant is not required.
    var canUsePeek: Bool { isAccessibilityGranted }
    
    /// Full Disk Access can't be queried directly via a clean API.
    /// We probe a protected path (Safari bookmarks DB) as a proxy.
    var isFullDiskAccessGranted: Bool {
        let protectedPath = ("~/Library/Safari/Bookmarks.plist" as NSString).expandingTildeInPath
        return FileManager.default.isReadableFile(atPath: protectedPath)
    }
    
    func requestInputMonitoring() {
        // CGRequestListenEventAccess can be satisfied by Accessibility without
        // registering an Input Monitoring entry. Request HID access explicitly.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
    
    func checkPermissionStatusChanged() -> (inputMonitoring: Bool, accessibility: Bool, fullDiskAccess: Bool) {
        let currentInputMonitoring = isInputMonitoringGranted
        let currentAccessibility = AXIsProcessTrusted()
        let currentFullDiskAccess = isFullDiskAccessGranted
        return (currentInputMonitoring, currentAccessibility, currentFullDiskAccess)
    }
    
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    func openInputMonitoringSettings() {
        // Opening the preference pane alone does not register this app with TCC.
        if !isInputMonitoringGranted { requestInputMonitoring() }
        openPrivacySettings(anchor: "Privacy_ListenEvent")
    }
    
    func openAccessibilitySettings() {
        if !isAccessibilityGranted { requestAccessibility() }
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    func openFullDiskAccessSettings() {
        // macOS has no public request API for Full Disk Access. Offer manual
        // addition through the guide rather than probing files to trigger it.
        openPrivacySettings(anchor: "Privacy_AllFiles")
    }

    private func openPrivacySettings(anchor: String) {
        let deepLink = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        if NSWorkspace.shared.open(deepLink) { return }
        let privacy = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        if !NSWorkspace.shared.open(privacy) {
            showManualSetupHelp(for: NSApp.keyWindow)
        }
    }

    func showManualSetupHelp(for window: NSWindow?) {
        let appURL = Bundle.main.bundleURL
        let alert = NSAlert()
        alert.messageText = "Add Glance to System Settings".localized
        alert.informativeText = "Open System Settings > Privacy & Security, then the permission you want to enable. If Glance is missing, click +, press Command-Shift-G, and enter the app path below. Select Glance, click Open, then turn on its switch.".localized
            + "\n\n" + appURL.path + "\n\n"
            + "If you are running Glance from a downloaded disk image, move it to Applications and reopen it there before granting permissions. If an older Glance entry does not work, remove it and add the current app again.".localized
        alert.addButton(withTitle: "Show Glance in Finder".localized)
        alert.addButton(withTitle: "Copy App Path".localized)
        alert.addButton(withTitle: "Not Now".localized)
        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([appURL])
            } else if response == .alertSecondButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appURL.path, forType: .string)
            }
        }
        if let window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else if window == nil {
            handleResponse(alert.runModal())
        }
    }
}
