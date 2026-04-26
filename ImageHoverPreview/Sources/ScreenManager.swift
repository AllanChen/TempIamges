import AppKit

class ScreenManager {
    static let shared = ScreenManager()

    func screenForMouseLocation(_ location: CGPoint) -> NSScreen? {
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    func adjustedFrame(for panelSize: NSSize, at mouseLocation: CGPoint, offset: CGPoint = CGPoint(x: 20, y: 20)) -> NSRect {
        guard let screen = screenForMouseLocation(mouseLocation) else {
            return NSRect(origin: mouseLocation, size: panelSize)
        }

        let screenFrame = screen.visibleFrame
        let screenHeight = screen.frame.height

        let appKitY = screenHeight - mouseLocation.y

        var originX = mouseLocation.x + offset.x
        var originY = appKitY - offset.y - panelSize.height

        if originX + panelSize.width > screenFrame.maxX {
            originX = mouseLocation.x - offset.x - panelSize.width
        }

        if originX < screenFrame.minX {
            originX = screenFrame.minX
        }

        if originY < screenFrame.minY {
            originY = appKitY + offset.y
        }

        if originY + panelSize.height > screenFrame.maxY {
            originY = screenFrame.maxY - panelSize.height
        }

        return NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height)
    }

    func scaleFactorForMouseLocation(_ location: CGPoint) -> CGFloat {
        return screenForMouseLocation(location)?.backingScaleFactor ?? 1.0
    }
}
