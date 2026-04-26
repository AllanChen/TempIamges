import Foundation
import ApplicationServices
import AppKit

func getTextAtMousePosition() -> (String?, Double) {
    let startTime = CFAbsoluteTimeGetCurrent()
    
    let mouseLocation = NSEvent.mouseLocation
    let screenHeight = NSScreen.main?.frame.height ?? 0
    let axY = screenHeight - mouseLocation.y
    
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    
    let result = AXUIElementCopyElementAtPosition(systemWide, Float(mouseLocation.x), Float(axY), &element)
    
    guard result == .success, let el = element else {
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return (nil, elapsed)
    }
    
    var text: String? = nil
    var value: CFTypeRef?
    
    if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value) == .success, let val = value {
        let str = CFGetTypeID(val) == CFStringGetTypeID() ? (val as! CFString) as String : nil
        if let s = str, !s.isEmpty {
            text = s
        }
    }
    
    if text == nil {
        if AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &value) == .success, let val = value {
            let str = CFGetTypeID(val) == CFStringGetTypeID() ? (val as! CFString) as String : nil
            if let s = str, !s.isEmpty {
                text = s
            }
        }
    }
    
    if text == nil {
        if AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &value) == .success, let val = value {
            let str = CFGetTypeID(val) == CFStringGetTypeID() ? (val as! CFString) as String : nil
            if let s = str, !s.isEmpty {
                text = s
            }
        }
    }
    
    if text == nil {
        if AXUIElementCopyAttributeValue(el, kAXRoleDescriptionAttribute as CFString, &value) == .success, let val = value {
            let str = CFGetTypeID(val) == CFStringGetTypeID() ? (val as! CFString) as String : nil
            if let s = str, !s.isEmpty {
                text = s
            }
        }
    }
    
    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
    return (text, elapsed)
}

func getRoleAtMousePosition() -> String? {
    let mouseLocation = NSEvent.mouseLocation
    let screenHeight = NSScreen.main?.frame.height ?? 0
    let axY = screenHeight - mouseLocation.y
    
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    
    let result = AXUIElementCopyElementAtPosition(systemWide, Float(mouseLocation.x), Float(axY), &element)
    
    guard result == .success, let el = element else {
        return nil
    }
    
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &value) == .success, let val = value {
        if CFGetTypeID(val) == CFStringGetTypeID() {
            return (val as! CFString) as String
        }
    }
    return nil
}

print("=== Accessibility Text Extraction Prototype ===")
print("Hover mouse over text in any application.")
print("Press Ctrl+C to stop.")
print("")

var lastText: String? = nil

while true {
    let (text, latency) = getTextAtMousePosition()
    let role = getRoleAtMousePosition()
    let location = NSEvent.mouseLocation
    
    if let t = text, t != lastText {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] POS:(\(Int(location.x)), \(Int(location.y))) ROLE:\(role ?? "none") LATENCY:\(String(format: "%.2f", latency))ms")
        print("  TEXT: \(t)")
        print("")
        lastText = t
    } else if text == nil && lastText != nil {
        lastText = nil
    }
    
    usleep(100_000)
}
