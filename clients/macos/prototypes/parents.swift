import Foundation
import ApplicationServices
import AppKit

let mouseLocation = NSEvent.mouseLocation
let screenHeight = NSScreen.main?.frame.height ?? 0
let axY = screenHeight - mouseLocation.y

let systemWide = AXUIElementCreateSystemWide()
var element: AXUIElement?

let result = AXUIElementCopyElementAtPosition(systemWide, Float(mouseLocation.x), Float(axY), &element)

if result == .success, let el = element {
    var current: AXUIElement = el
    var depth = 0
    while true {
        var roleValue: CFTypeRef?
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)
        AXUIElementCopyAttributeValue(current, kAXTitleAttribute as CFString, &titleValue)
        
        let role = roleValue != nil && CFGetTypeID(roleValue!) == CFStringGetTypeID() ? (roleValue! as! CFString) as String : "unknown"
        let title = titleValue != nil && CFGetTypeID(titleValue!) == CFStringGetTypeID() ? (titleValue! as! CFString) as String : ""
        
        print("Depth \(depth): \(role) | '\(title)'")
        
        var parentValue: CFTypeRef?
        let parentResult = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
        if parentResult != .success || parentValue == nil {
            print("No parent (result: \(parentResult.rawValue))")
            break
        }
        current = (parentValue as! AXUIElement)
        depth += 1
        if depth > 20 {
            print("Max depth reached")
            break
        }
    }
} else {
    print("No element")
}
