import AppKit

/// The tray glyph from Figma "Brand · App Icon" › "Tray · B · Peek": the Glance
/// peeker as a one-colour template image on the 18 pt grid. A dome head looks
/// over the frame's rim with both hands on it; eyes are knocked out of the
/// head. Peek off raises the hands over the eyes; running tasks play a
/// four-frame "glancing around" loop.
///
/// Drawn in code rather than shipped as six image sets so every state shares
/// one geometry and stays in step with the Figma source.
enum MenuBarCharacterIcon {
    enum State: CaseIterable {
        case `default`, peekOff, lookLeft, lookRight, blink
    }

    /// Frame order for the running-task loop: glance left → centre → right →
    /// centre, three times, then one blink. At 280 ms a frame that is a blink
    /// roughly every 3.6 s, as the Figma board specifies.
    static let runningSequence: [State] = [
        .lookLeft, .default, .lookRight, .default,
        .lookLeft, .default, .lookRight, .default,
        .lookLeft, .default, .lookRight, .default,
        .blink
    ]
    static let frameInterval: TimeInterval = 0.28

    private static var cache: [State: NSImage] = [:]

    static func image(for state: State) -> NSImage {
        if let cached = cache[state] { return cached }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            draw(state)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glance"
        cache[state] = image
        return image
    }

    // MARK: - Geometry (Figma "Tray · B · Peek"; 1 unit = 1 pt on the 18 pt canvas, top-left origin)

    private static func pill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2)
    }

    private static func draw(_ state: State) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill()

        // Dome head resting on the frame's rim, and the rim itself.
        let head = NSBezierPath()
        // The base dips under the rim so no seam shows where they meet.
        head.move(to: NSPoint(x: 3.6, y: 13.4))
        head.line(to: NSPoint(x: 3.6, y: 12.6))
        head.curve(to: NSPoint(x: 9, y: 5.6), controlPoint1: NSPoint(x: 3.6, y: 8.9), controlPoint2: NSPoint(x: 6, y: 5.6))
        head.curve(to: NSPoint(x: 14.4, y: 12.6), controlPoint1: NSPoint(x: 12, y: 5.6), controlPoint2: NSPoint(x: 14.4, y: 8.9))
        head.line(to: NSPoint(x: 14.4, y: 13.4))
        head.close()
        head.fill()
        pill(1.4, 12.6, 15.2, 2.2).fill()

        // Knockouts clear alpha, which is what a template image needs.
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        switch state {
        case .peekOff:
            // A thin gap lets the raised hands read against the head.
            pill(4.75, 8.25, 3.9, 2.9).fill()
            pill(9.35, 8.25, 3.9, 2.9).fill()
        case .blink:
            pill(6.2, 9.4, 2.1, 0.7).fill()
            pill(9.7, 9.4, 2.1, 0.7).fill()
        default:
            let dx: CGFloat = state == .lookLeft ? -0.8 : (state == .lookRight ? 0.8 : 0)
            for cx in [7.25, 10.75] as [CGFloat] {
                NSBezierPath(ovalIn: NSRect(x: cx + dx - 1.15, y: 8.55, width: 2.3, height: 2.3)).fill()
            }
        }
        ctx.restoreGState()

        // Hands: on the rim, or raised over the eyes when Peek is off.
        if state == .peekOff {
            pill(5.15, 8.65, 3.1, 2.1).fill()
            pill(9.75, 8.65, 3.1, 2.1).fill()
        } else {
            pill(3.2, 11.6, 3.4, 2.1).fill()
            pill(11.4, 11.6, 3.4, 2.1).fill()
        }
    }
}
