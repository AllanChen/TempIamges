import Foundation
import ApplicationServices
import AppKit

func measureLatency() -> Double {
    let startTime = CFAbsoluteTimeGetCurrent()
    
    let mouseLocation = NSEvent.mouseLocation
    let screenHeight = NSScreen.main?.frame.height ?? 0
    let axY = screenHeight - mouseLocation.y
    
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    
    let result = AXUIElementCopyElementAtPosition(systemWide, Float(mouseLocation.x), Float(axY), &element)
    
    guard result == .success, let el = element else {
        return (CFAbsoluteTimeGetCurrent() - startTime) * 1000
    }
    
    var text: String? = nil
    var value: CFTypeRef?
    
    if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value) == .success, let val = value {
        if CFGetTypeID(val) == CFStringGetTypeID() {
            text = (val as! CFString) as String
        }
    }
    
    if text == nil {
        if AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &value) == .success, let val = value {
            if CFGetTypeID(val) == CFStringGetTypeID() {
                text = (val as! CFString) as String
            }
        }
    }
    
    if text == nil {
        if AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &value) == .success, let val = value {
            if CFGetTypeID(val) == CFStringGetTypeID() {
                text = (val as! CFString) as String
            }
        }
    }
    
    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
    return elapsed
}

let latency = measureLatency()
print("Extraction latency: \(String(format: "%.3f", latency))ms")
