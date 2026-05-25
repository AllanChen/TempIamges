import AppKit
import ApplicationServices

class PermissionManager: NSObject {
    static let shared = PermissionManager()
    
    var isInputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }
    
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
    
    /// Full Disk Access can't be queried directly via a clean API.
    /// We probe a protected path (Safari bookmarks DB) as a proxy.
    var isFullDiskAccessGranted: Bool {
        let protectedPath = ("~/Library/Safari/Bookmarks.plist" as NSString).expandingTildeInPath
        return FileManager.default.isReadableFile(atPath: protectedPath)
    }
    
    func requestInputMonitoring() {
        CGRequestListenEventAccess()
    }
    
    func checkPermissionStatusChanged() -> (inputMonitoring: Bool, accessibility: Bool, fullDiskAccess: Bool) {
        let currentInputMonitoring = CGPreflightListenEventAccess()
        let currentAccessibility = AXIsProcessTrusted()
        let currentFullDiskAccess = isFullDiskAccessGranted
        return (currentInputMonitoring, currentAccessibility, currentFullDiskAccess)
    }
    
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
