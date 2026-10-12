import AppKit

/// A Widget's optional result URL action stays separate from the generated bitmap.
final class WidgetResultURLButton: NSControl {
    var onPress: (() -> Void)?
    private let icon = NSImageView()
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.accent.withAlphaComponent(0.72))
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        icon.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        icon.contentTintColor = PanelStyle.accent
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.frame = NSRect(x: 9, y: 9, width: 16, height: 16)
        addSubview(icon)
        toolTip = "Copy result URL".localized
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Copy result URL".localized)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar.blended(withFraction: 0.12, of: PanelStyle.accent) ?? PanelStyle.inspectToolbar)
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
    }
}
