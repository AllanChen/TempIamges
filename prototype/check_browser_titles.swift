import Foundation
import CoreGraphics

let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

for window in windowList {
    if let name = window[kCGWindowOwnerName as String] as? String,
       name == "Google Chrome" || name == "Safari" {
        let pid = window[kCGWindowOwnerPID as String] as? Int ?? 0
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let title = window[kCGWindowName as String] as? String ?? ""
        let x = bounds["X"] ?? 0
        let y = bounds["Y"] ?? 0
        let w = bounds["Width"] ?? 0
        let h = bounds["Height"] ?? 0
        print("\(name) [pid:\(pid)] title='\(title)' (\(Int(x)),\(Int(y))) (\(Int(w))x\(Int(h)))")
    }
}
