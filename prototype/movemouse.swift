import Foundation
import CoreGraphics

let args = CommandLine.arguments
if args.count > 2 {
    let x = CGFloat(Double(args[1])!)
    let y = CGFloat(Double(args[2])!)
    let pt = CGPoint(x: x, y: y)
    let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)
    move?.post(tap: .cghidEventTap)
} else {
    print("Usage: movemouse <x> <y>")
}
