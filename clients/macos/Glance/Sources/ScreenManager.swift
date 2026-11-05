import AppKit

class ScreenManager {
    static let shared = ScreenManager()

    /// Window chrome needs a usable canvas even for tiny or extremely narrow
    /// media. The viewport aspect-fits the media inside this size; it must not
    /// stretch the media to the window's aspect ratio.
    static func mediaWindowSize(preferred: NSSize, minimum: NSSize, maximum: NSSize) -> NSSize {
        let ceiling = NSSize(width: max(1, maximum.width), height: max(1, maximum.height))
        let floor = NSSize(width: min(minimum.width, ceiling.width),
                           height: min(minimum.height, ceiling.height))
        guard preferred.width.isFinite, preferred.height.isFinite,
              preferred.width > 0, preferred.height > 0 else { return floor }
        let scale = min(1, ceiling.width / preferred.width, ceiling.height / preferred.height)
        return NSSize(width: min(ceiling.width, max(floor.width, (preferred.width * scale).rounded())),
                      height: min(ceiling.height, max(floor.height, (preferred.height * scale).rounded())))
    }

    func screenForMouseLocation(_ location: CGPoint) -> NSScreen? {
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    func adjustedFrame(for panelSize: NSSize, at mouseLocation: CGPoint, offset: CGPoint = CGPoint(x: 20, y: 20)) -> NSRect {
        guard let screen = screenForMouseLocation(mouseLocation) else {
            return NSRect(origin: mouseLocation, size: panelSize)
        }

        let screenFrame = screen.visibleFrame

        var originX = mouseLocation.x + offset.x
        var originY = mouseLocation.y - panelSize.height / 2

        if originX + panelSize.width > screenFrame.maxX {
            originX = mouseLocation.x - offset.x - panelSize.width
        }

        if originX < screenFrame.minX {
            originX = screenFrame.minX
        }

        if originY < screenFrame.minY {
            originY = screenFrame.minY
        }

        if originY + panelSize.height > screenFrame.maxY {
            originY = screenFrame.maxY - panelSize.height
        }

        return NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height)
    }

    /// Center `panelSize` on `screen`, shrinking it to fit and clamping the
    /// origin so the entire window stays within the visible area (menu bar and
    /// Dock excluded). Guarantees the window is fully on-screen, even when the
    /// requested size is taller or wider than the display.
    func centerFrame(for panelSize: NSSize, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let w = min(panelSize.width, visible.width)
        let h = min(panelSize.height, visible.height)
        var originX = visible.midX - w / 2
        var originY = visible.midY - h / 2
        originX = max(visible.minX, min(originX, visible.maxX - w))
        originY = max(visible.minY, min(originY, visible.maxY - h))
        return NSRect(x: originX, y: originY, width: w, height: h)
    }

    func scaleFactorForMouseLocation(_ location: CGPoint) -> CGFloat {
        return screenForMouseLocation(location)?.backingScaleFactor ?? 1.0
    }

    /// Centered, fully-on-screen frame on whichever screen the cursor is on.
    func contentFrame(for panelSize: NSSize) -> NSRect {
        let mousePos = NSEvent.mouseLocation
        guard let screen = screenForMouseLocation(mousePos) else {
            return NSRect(origin: mousePos, size: panelSize)
        }
        return centerFrame(for: panelSize, on: screen)
    }

    /// Centered, fully-on-screen frame on whichever screen contains `location`
    /// (falls back to the main screen). Used to open panels centered relative
    /// to the cursor's screen instead of anchored to one side.
    func centeredFrame(for panelSize: NSSize, near location: CGPoint) -> NSRect {
        let screen = screenForMouseLocation(location) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else {
            return NSRect(origin: location, size: panelSize)
        }
        return centerFrame(for: panelSize, on: screen)
    }

    /// Clamp an arbitrary frame so it stays fully within its screen's visible
    /// area, shrinking it if it is larger. Used to keep restored (user-dragged)
    /// positions on-screen.
    func clampedToVisible(_ frame: NSRect) -> NSRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = screenForMouseLocation(center) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return frame }
        let visible = screen.visibleFrame
        let w = min(frame.width, visible.width)
        let h = min(frame.height, visible.height)
        var originX = frame.origin.x
        var originY = frame.origin.y
        originX = max(visible.minX, min(originX, visible.maxX - w))
        originY = max(visible.minY, min(originY, visible.maxY - h))
        return NSRect(x: originX, y: originY, width: w, height: h)
    }
}
