import Foundation
import CoreGraphics

let esc = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: true)
esc?.flags = .maskSecondaryFn
esc?.post(tap: .cghidEventTap)

let escUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: false)
escUp?.post(tap: .cghidEventTap)
