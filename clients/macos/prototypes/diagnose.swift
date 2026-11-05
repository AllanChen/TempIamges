import Foundation
import ApplicationServices
import AppKit

let mouseLocation = NSEvent.mouseLocation
let screenHeight = NSScreen.main?.frame.height ?? 0
let axY = screenHeight - mouseLocation.y

print("Mouse location: \(mouseLocation)")
print("Screen height: \(screenHeight)")
print("AX Y (flipped): \(axY)")

let systemWide = AXUIElementCreateSystemWide()
var element: AXUIElement?

let result = AXUIElementCopyElementAtPosition(systemWide, Float(mouseLocation.x), Float(axY), &element)

print("CopyElementAtPosition result: \(result.rawValue)")

if result == .success, let el = element {
    print("Got element")
    
    let attributes = [
        kAXValueAttribute,
        kAXDescriptionAttribute,
        kAXTitleAttribute,
        kAXRoleDescriptionAttribute,
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXHelpAttribute,
        kAXURLAttribute
    ]
    
    for attr in attributes {
        var value: CFTypeRef?
        let attrResult = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
        if attrResult == .success, let val = value {
            let typeID = CFGetTypeID(val)
            var strVal = "unknown type"
            if typeID == CFStringGetTypeID() {
                strVal = (val as! CFString) as String
            } else if typeID == AXValueGetTypeID() {
                strVal = "AXValue"
            } else if typeID == CFArrayGetTypeID() {
                strVal = "Array"
            }
            print("  \(attr): \(strVal)")
        } else {
            print("  \(attr): failed (\(attrResult.rawValue))")
        }
    }
} else {
    print("No element found")
}
