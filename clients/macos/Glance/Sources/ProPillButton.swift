import AppKit

/// The Home window's Pro entry (Figma "Home / Pro Entry / Layout Options" · Option C): a small pill at the right of the
/// titlebar, always visible, so nothing is added to the window body. A flame, "Pro" and the price in the accent color;
/// the one-time-purchase and lifetime-updates promise is the tooltip. Hover, pressed (scaled to 0.97) and a keyboard
/// focus ring are separate states. Figma coordinates are top-origin, so the view is flipped.
final class ProPillButton: NSControl {
    static let pillHeight: CGFloat = 28
    /// Room around the pill for the keyboard focus ring (it sits 3pt outside).
    static let margin: CGFloat = 3

    private static let flame = NSColor(srgbRed: 1, green: 138 / 255, blue: 76 / 255, alpha: 1)
    private static let font = NSFont.systemFont(ofSize: 12, weight: .semibold)

    /// The price, e.g. "$9.99". Without one the pill reads "Upgrade to Pro".
    var price: String? { didSet { needsDisplay = true } }

    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private var pillRect: NSRect { bounds.insetBy(dx: Self.margin, dy: Self.margin) }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled && !isHidden }
    override var focusRingType: NSFocusRingType { get { .none } set {} }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Content

    private var labelText: String { price == nil ? "Upgrade to Pro".localized : "Pro" }
    private var priceText: String? { price.map { String(format: "from %@".localized, $0) } }
    private func width(of text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: Self.font]).width)
    }

    /// The control's width: 12pt padding, the flame (11), 7, "Pro", 8, the price, 12pt padding, plus the focus margin.
    var preferredWidth: CGFloat {
        var pill: CGFloat = 12 + 11 + 7 + width(of: labelText) + 12
        if let priceText { pill += 8 + width(of: priceText) }
        return ceil(pill) + Self.margin * 2
    }
    var preferredHeight: CGFloat { Self.pillHeight + Self.margin * 2 }

    // MARK: Drawing

    private var showsFocusRing: Bool { window?.firstResponder === self && window?.isKeyWindow == true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = pillRect
        if showsFocusRing {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 15, yRadius: 15)
            ring.lineWidth = 2
            PanelStyle.accent.withAlphaComponent(0.65).setStroke()
            ring.stroke()
        }
        NSGraphicsContext.saveGraphicsState()
        if pressed {
            let scale = NSAffineTransform()
            scale.translateX(by: rect.midX, yBy: rect.midY)
            scale.scaleX(by: 0.97, yBy: 0.97)
            scale.translateX(by: -rect.midX, yBy: -rect.midY)
            scale.concat()
        }
        let fillAlpha: CGFloat = pressed ? 0.32 : (hovering ? 0.24 : 0.14)
        let strokeAlpha: CGFloat = hovering || pressed ? 0.8 : 0.55
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        PanelStyle.accent.withAlphaComponent(fillAlpha).setFill()
        path.fill()
        PanelStyle.accent.withAlphaComponent(strokeAlpha).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawFlame(at: NSPoint(x: rect.minX + 12, y: rect.minY + 7))
        var x = rect.minX + 12 + 11 + 7
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: PanelStyle.textPrimary]
        let labelSize = (labelText as NSString).size(withAttributes: labelAttributes)
        (labelText as NSString).draw(at: NSPoint(x: x, y: rect.midY - labelSize.height / 2), withAttributes: labelAttributes)
        x += ceil(labelSize.width) + 8
        if let priceText {
            let priceAttributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: PanelStyle.accent]
            let priceSize = (priceText as NSString).size(withAttributes: priceAttributes)
            (priceText as NSString).draw(at: NSPoint(x: x, y: rect.midY - priceSize.height / 2), withAttributes: priceAttributes)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The flame from the Figma study (a vector, so it looks the same on every system), 11×14.
    private func drawFlame(at origin: NSPoint) {
        let path = NSBezierPath()
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x - 1, y: origin.y + y) }
        path.move(to: point(6, 0))
        path.curve(to: point(1, 8.6), controlPoint1: point(6, 0), controlPoint2: point(1, 4.2))
        path.curve(to: point(6, 14), controlPoint1: point(1, 11.6), controlPoint2: point(3.2, 14))
        path.curve(to: point(11, 8.6), controlPoint1: point(8.8, 14), controlPoint2: point(11, 11.6))
        path.curve(to: point(9, 4.4), controlPoint1: point(11, 6.8), controlPoint2: point(10, 5.4))
        path.curve(to: point(7.1, 6.7), controlPoint1: point(8.8, 5.9), controlPoint2: point(7.9, 6.7))
        path.curve(to: point(6, 0), controlPoint1: point(7.1, 4), controlPoint2: point(6.4, 1.8))
        path.close()
        Self.flame.setFill()
        path.fill()
    }

    // MARK: Interaction

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() { addCursorRect(pillRect, cursor: .pointingHand) }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = pillRect.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, pressed else { return }
        pressed = false
        if pillRect.contains(convert(event.locationInWindow, from: nil)) { sendAction(action, to: target) }
    }

    /// Space and Return press the focused pill.
    override func keyDown(with event: NSEvent) {
        if isEnabled, [36, 49, 76].contains(event.keyCode) { sendAction(action, to: target) } else { super.keyDown(with: event) }
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
}
