import AppKit

/// A Widget's optional result URL action stays separate from the generated bitmap.
/// Drawn as a Figma Shizuka `IconButton`: 16 pt glyph, quiet wash on hover.
final class WidgetResultURLButton: NSControl {
    var onPress: (() -> Void)?
    private let icon = NSImageView()
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        layer?.borderWidth = 0
        layer?.backgroundColor = NSColor.clear.cgColor
        icon.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        icon.contentTintColor = InspectInk.text2
        icon.imageScaling = .scaleNone
        addSubview(icon)
        toolTip = "Copy result URL".localized
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Copy result URL".localized)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16)
    }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
    override func mouseDown(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.controlFill)
        icon.contentTintColor = InspectInk.text1
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        icon.contentTintColor = InspectInk.text2
    }
}
