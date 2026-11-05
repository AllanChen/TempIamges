import AppKit
import AVFoundation
import AVKit
import Network
import WebKit

final class WarmVideoTimeline: NSView {
    var value = 0.0 { didSet { needsDisplay = true } }; var maximum = 1.0 { didSet { needsDisplay = true } }; var onChange: ((Double) -> Void)?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { let track = NSRect(x: 7, y: bounds.midY - 2, width: max(1, bounds.width - 14), height: 4); PanelStyle.inspectLine.setFill(); NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill(); let f = maximum > 0 ? min(1, max(0, value / maximum)) : 0; PanelStyle.accent.setFill(); NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * f, height: track.height), xRadius: 2, yRadius: 2).fill(); NSBezierPath(ovalIn: NSRect(x: track.minX + track.width * f - 7, y: bounds.midY - 7, width: 14, height: 14)).fill() }
    override func mouseDown(with event: NSEvent) { update(event) }; override func mouseDragged(with event: NSEvent) { update(event) }
    private func update(_ event: NSEvent) { let x = convert(event.locationInWindow, from: nil).x; let f = min(1, max(0, (x - 7) / max(1, bounds.width - 14))); onChange?(f * maximum) }
}

/// Shared frosted chrome for both floating bars in the v4 reference.
final class VideoPlaybackBar: NSView {
    private let blur = PanelStyle.makeBarBlur()
    private let tint = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.shadowColor = NSColor(srgbRed: 20 / 255, green: 23 / 255,
                                     blue: 26 / 255, alpha: 0.24).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        layer?.shadowRadius = 12
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 15
        blur.layer?.masksToBounds = true
        addSubview(blur)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(srgbRed: 22 / 255, green: 23 / 255,
                                              blue: 25 / 255, alpha: 0.90).cgColor
        blur.addSubview(tint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = blur.bounds
    }
}

/// Explicit Figma text frames, without NSTextField cell insets or baselines.
final class VideoTimeLabel: NSView {
    var stringValue: String { didSet { needsDisplay = true; setAccessibilityValue(stringValue) } }
    init(_ value: String) {
        stringValue = value
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityValue(value)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let text = NSAttributedString(string: stringValue, attributes: [
            .font: PanelStyle.inspectFont(ofSize: 12, weight: .medium),
            .foregroundColor: PanelStyle.textPrimary
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
