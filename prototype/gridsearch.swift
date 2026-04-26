import Foundation
import ApplicationServices
import AppKit

func checkTextAt(x: Float, y: Float) -> String? {
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    
    let result = AXUIElementCopyElementAtPosition(systemWide, x, y, &element)
    guard result == .success, let el = element else {
        return nil
    }
    
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value) == .success, let val = value {
        if CFGetTypeID(val) == CFStringGetTypeID() {
            let s = (val as! CFString) as String
            if !s.isEmpty {
                return s
            }
        }
    }
    
    if AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &value) == .success, let val = value {
        if CFGetTypeID(val) == CFStringGetTypeID() {
            let s = (val as! CFString) as String
            if !s.isEmpty {
                return s
            }
        }
    }
    
    if AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &value) == .success, let val = value {
        if CFGetTypeID(val) == CFStringGetTypeID() {
            let s = (val as! CFString) as String
            if !s.isEmpty {
                return s
            }
        }
    }
    
    return nil
}

let windowX = -553
let windowY = -1127
let windowW = 2048
let windowH = 1127

let step = 200
for y in stride(from: windowY + 100, to: windowY + windowH, by: step) {
    for x in stride(from: windowX + 100, to: windowX + windowW, by: step) {
        if let text = checkTextAt(x: Float(x), y: Float(y)) {
            print("Found text at (\(x), \(y)): \(text)")
        }
    }
}

print("Grid search complete.")
