import AppKit

/// A Widget's optional result URL action stays separate from the generated bitmap.
/// Shown as a labelled pill over the result image's top-right corner: a 16 pt
/// copy glyph and "Copy URL" on a translucent ink/1 plate so it reads on any photo.
final class WidgetResultURLButton: NSControl {
    var onPress: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "Copy URL".localized)
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { updateAppearance() } }

    /// Glyph, 6 pt gap, label, with 10 / 12 pt side padding; 28 pt tall.
    var preferredSize: NSSize {
        let text = ceil(label.attributedStringValue.size().width)
        return NSSize(width: 10 + 16 + 6 + text + 12, height: 28)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        icon.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        icon.imageScaling = .scaleNone
        addSubview(icon)
        label.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byClipping
        addSubview(label)
        toolTip = "Copy result URL".localized
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Copy result URL".localized)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 10, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: 32, y: ((bounds.height - height) / 2).rounded(),
                             width: max(0, bounds.width - 32 - 12), height: height)
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
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func updateAppearance() {
        let plate = hovering ? InspectInk.ink3 : InspectInk.ink1
        layer?.backgroundColor = PanelStyle.resolvedCG(plate.withAlphaComponent(0.92))
        layer?.borderColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
        icon.contentTintColor = InspectInk.text1
        label.textColor = InspectInk.text1
    }
}
