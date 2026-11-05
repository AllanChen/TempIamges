import Foundation
import CoreGraphics

let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

for window in windowList {
    if let pid = window[kCGWindowOwnerPID as String] as? Int,
       let name = window[kCGWindowOwnerName as String] as? String,
       let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] {
        let x = bounds["X"] ?? 0
        let y = bounds["Y"] ?? 0
        let w = bounds["Width"] ?? 0
        let h = bounds["Height"] ?? 0
        print("\(name) [pid:\(pid)] (\(Int(x)),\(Int(y))) (\(Int(w))x\(Int(h)))")
    }
}
