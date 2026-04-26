import Foundation
import ApplicationServices

func findWindows() {
    let systemWide = AXUIElementCreateSystemWide()
    var apps: CFTypeRef?
    
    guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &apps) == .success ||
          AXUIElementCopyAttributeValue(systemWide, "AXApplications" as CFString, &apps) == .success else {
        print("Could not get applications")
        return
    }
    
    var focusedApp: CFTypeRef?
    if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success, let fa = focusedApp {
        var pid: pid_t = 0
        AXUIElementGetPid(fa as! AXUIElement, &pid)
        print("Focused app PID: \(pid)")
        
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(fa as! AXUIElement, kAXWindowsAttribute as CFString, &windows) == .success, let w = windows {
            if CFGetTypeID(w) == CFArrayGetTypeID() {
                let arr = w as! CFArray
                let count = CFArrayGetCount(arr)
                print("Window count: \(count)")
                for i in 0..<count {
                    let win = Unmanaged<AXUIElement>.fromOpaque(CFArrayGetValueAtIndex(arr, i)).takeUnretainedValue()
                    
                    var posValue: CFTypeRef?
                    var sizeValue: CFTypeRef?
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posValue)
                    AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeValue)
                    AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleValue)
                    
                    var posStr = "unknown"
                    if let pv = posValue, CFGetTypeID(pv) == AXValueGetTypeID() {
                        var pt = CGPoint.zero
                        if AXValueGetValue(pv as! AXValue, .cgPoint, &pt) {
                            posStr = "(\(Int(pt.x)), \(Int(pt.y)))"
                        }
                    }
                    
                    var sizeStr = "unknown"
                    if let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID() {
                        var sz = CGSize.zero
                        if AXValueGetValue(sv as! AXValue, .cgSize, &sz) {
                            sizeStr = "(\(Int(sz.width)), \(Int(sz.height)))"
                        }
                    }
                    
                    let title = titleValue != nil && CFGetTypeID(titleValue!) == CFStringGetTypeID() ? (titleValue! as! CFString) as String : ""
                    
                    print("  Window \(i): title='\(title)' pos=\(posStr) size=\(sizeStr)")
                }
            }
        }
    }
}

findWindows()
