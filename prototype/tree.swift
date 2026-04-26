import Foundation
import ApplicationServices
import AppKit

func printElement(_ el: AXUIElement, depth: Int = 0) {
    let indent = String(repeating: "  ", count: depth)
    
    var roleValue: CFTypeRef?
    var titleValue: CFTypeRef?
    var valueValue: CFTypeRef?
    var descValue: CFTypeRef?
    
    AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleValue)
    AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleValue)
    AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueValue)
    AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descValue)
    
    let role = roleValue != nil && CFGetTypeID(roleValue!) == CFStringGetTypeID() ? (roleValue! as! CFString) as String : "unknown"
    let title = titleValue != nil && CFGetTypeID(titleValue!) == CFStringGetTypeID() ? (titleValue! as! CFString) as String : ""
    let value = valueValue != nil && CFGetTypeID(valueValue!) == CFStringGetTypeID() ? (valueValue! as! CFString) as String : ""
    let desc = descValue != nil && CFGetTypeID(descValue!) == CFStringGetTypeID() ? (descValue! as! CFString) as String : ""
    
    print("\(indent)\(role) | title='\(title)' value='\(value)' desc='\(desc)'")
    
    var children: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success, let ch = children {
        if CFGetTypeID(ch) == CFArrayGetTypeID() {
            let arr = ch as! CFArray
            let count = CFArrayGetCount(arr)
            for i in 0..<count {
                let child = Unmanaged<AXUIElement>.fromOpaque(CFArrayGetValueAtIndex(arr, i)).takeUnretainedValue()
                printElement(child, depth: depth + 1)
            }
        }
    }
}

let mouseLocation = NSEvent.mouseLocation
let screenHeight = NSScreen.main?.frame.height ?? 0
let axY = screenHeight - mouseLocation.y

let systemWide = AXUIElementCreateSystemWide()
var element: AXUIElement?

let result = AXUIElementCopyElementAtPosition(systemWide, Float(mouseLocation.x), Float(axY), &element)

print("Mouse: \(mouseLocation), AX result: \(result.rawValue)")

if result == .success, let el = element {
    printElement(el)
} else {
    print("No element")
}
