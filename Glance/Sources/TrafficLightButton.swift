import AppKit

/// The red / yellow / green window buttons used by Glance's custom chrome.
/// Like the system ones, hovering any of the three reveals the glyphs on all
/// three (✕, −, ⤢); until then they are plain coloured dots.
///
/// The kind is read from the colour, because every window already passes the
/// same three system colours: red → close, yellow → minimize, green → zoom.
final class TrafficLightButton: NSControl {
    enum Kind { case close, minimize, zoom }

    private static let hoverChanged = Notification.Name("GlanceTrafficLightHoverChanged")
    private static let dotSize: CGFloat = 12

    private let kind: Kind
    private let dot = CALayer()
    private let glyph = CAShapeLayer()
    private var isPressed = false

    init(color: NSColor, target: AnyObject? = nil, action: Selector? = nil) {
        self.kind = Self.kind(for: color)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        dot.backgroundColor = PanelStyle.resolvedCG(color)
        dot.cornerRadius = Self.dotSize / 2
        dot.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        dot.shadowOpacity = 1
        dot.shadowOffset = CGSize(width: 0, height: -1)
        dot.shadowRadius = 1.5
        layer?.addSublayer(dot)

        glyph.fillColor = nil
        glyph.strokeColor = NSColor.black.withAlphaComponent(0.55).cgColor
        glyph.lineWidth = 1.2
        glyph.lineCap = .round
        glyph.lineJoin = .round
        glyph.isHidden = true
        dot.addSublayer(glyph)

        self.target = target
        self.action = action
        let label: String
        switch kind {
        case .close: label = "Close".localized
        case .minimize: label = "Minimize".localized
        case .zoom: label = "Zoom".localized
        }
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        NotificationCenter.default.addObserver(self, selector: #selector(groupHoverChanged(_:)),
                                               name: Self.hoverChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    private static func kind(for color: NSColor) -> Kind {
        let c = color.usingColorSpace(.sRGB) ?? color
        if c.greenComponent > 0.65 && c.redComponent > 0.8 { return .minimize }   // yellow  (244, 191, 79)
        if c.redComponent < 0.6 && c.greenComponent > 0.65 { return .zoom }       // green   (97, 197, 84)
        return .close                                                              // red     (237, 106, 94)
    }

    // MARK: Hover (shared by the three buttons in one titlebar)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { postHover(true) }
    override func mouseExited(with event: NSEvent) { postHover(false) }

    private func postHover(_ hovering: Bool) {
        NotificationCenter.default.post(name: Self.hoverChanged, object: superview,
                                        userInfo: ["hovering": hovering])
    }

    @objc private func groupHoverChanged(_ note: Notification) {
        guard let owner = note.object as? NSView, owner === superview else { return }
        glyph.isHidden = !((note.userInfo?["hovering"] as? Bool) ?? false)
    }

    // MARK: Drawing

    override func layout() {
        super.layout()
        let side = min(Self.dotSize, bounds.width, bounds.height)
        dot.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        dot.cornerRadius = side / 2
        glyph.frame = dot.bounds
        glyph.path = glyphPath(in: dot.bounds)
    }

    /// Glyphs follow the system's proportions inside a 12 pt dot.
    private func glyphPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        switch kind {
        case .close:
            let d: CGFloat = 2.3
            path.move(to: CGPoint(x: c.x - d, y: c.y - d)); path.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
            path.move(to: CGPoint(x: c.x - d, y: c.y + d)); path.addLine(to: CGPoint(x: c.x + d, y: c.y - d))
        case .minimize:
            path.move(to: CGPoint(x: c.x - 2.8, y: c.y)); path.addLine(to: CGPoint(x: c.x + 2.8, y: c.y))
        case .zoom:
            // Two small triangles pointing at opposite corners, like the system glyph.
            path.move(to: CGPoint(x: c.x - 2.4, y: c.y - 2.4)); path.addLine(to: CGPoint(x: c.x - 2.4, y: c.y + 0.4))
            path.move(to: CGPoint(x: c.x - 2.4, y: c.y - 2.4)); path.addLine(to: CGPoint(x: c.x + 0.4, y: c.y - 2.4))
            path.move(to: CGPoint(x: c.x + 2.4, y: c.y + 2.4)); path.addLine(to: CGPoint(x: c.x + 2.4, y: c.y - 0.4))
            path.move(to: CGPoint(x: c.x + 2.4, y: c.y + 2.4)); path.addLine(to: CGPoint(x: c.x - 0.4, y: c.y + 2.4))
        }
        return path
    }

    // MARK: Events

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        dot.opacity = 0.75
        // Track until release like a normal button: fire only if still inside.
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp {
                let inside = bounds.contains(convert(next.locationInWindow, from: nil))
                isPressed = false
                dot.opacity = 1
                if inside { sendAction(action, to: target) }
                return
            }
        }
        isPressed = false
        dot.opacity = 1
    }
}
