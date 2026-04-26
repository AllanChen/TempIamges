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
    
    func requestInputMonitoring() {
        CGRequestListenEventAccess()
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
}
