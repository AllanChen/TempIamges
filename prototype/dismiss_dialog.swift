import Foundation
import CoreGraphics

for _ in 0..<3 {
    let tabDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: true)
    tabDown?.post(tap: .cghidEventTap)
    let tabUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: false)
    tabUp?.post(tap: .cghidEventTap)
    usleep(100_000)
}

let retDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true)
retDown?.post(tap: .cghidEventTap)
let retUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: false)
retUp?.post(tap: .cghidEventTap)
