import AppKit

/// The tray glyph from Figma "Menu Bar Icon / Character": the Glance peeker
/// as a one-colour template image on the 18 pt grid. A round head looks over
/// the frame's top edge with both hands on it; eyes are knocked out of the
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

    // MARK: - Geometry (1 unit = 1 pt on the 18 pt canvas, top-left origin)

    private static func disc(_ cx: CGFloat, _ cy: CGFloat, _ d: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
    }

    private static func draw(_ state: State) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill()

        // Silhouette: head over the frame's top edge.
        disc(9, 8, 11).fill()
        NSBezierPath(roundedRect: NSRect(x: 1.5, y: 12.25, width: 15, height: 2.25),
                     xRadius: 1.125, yRadius: 1.125).fill()

        // Knockouts clear alpha, which is what a template image needs.
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        let covered = state == .peekOff
        if !covered {
            let dx: CGFloat = state == .lookLeft ? -0.9 : (state == .lookRight ? 0.9 : 0)
            for cx in [6.8, 11.2] as [CGFloat] {
                if state == .blink {
                    NSBezierPath(roundedRect: NSRect(x: cx + dx - 1.1, y: 7.3, width: 2.2, height: 0.7),
                                 xRadius: 0.35, yRadius: 0.35).fill()
                } else {
                    disc(cx + dx, 7.6, 2.2).fill()
                }
            }
        }
        // A thin gap around each hand separates it from whatever is behind.
        let hands: [(CGFloat, CGFloat, CGFloat)] = covered
            ? [(6.8, 8.0, 4.4), (11.2, 8.0, 4.4)]
            : [(5.2, 12.3, 3.2), (12.8, 12.3, 3.2)]
        for (cx, cy, d) in hands { disc(cx, cy, d + 1.0).fill() }
        ctx.restoreGState()

        for (cx, cy, d) in hands { disc(cx, cy, d).fill() }
    }
}
