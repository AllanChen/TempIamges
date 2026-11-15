import AppKit
import AVFoundation
import AVKit
import Network
import WebKit

/// Figma Shizuka `scrubber`: a 1 pt line/strong track, a 1 pt text/1 played
/// part and a 9 pt knob. The track is inset by half the knob so the knob stays
/// inside the view at both ends; the whole height takes clicks and drags.
final class WarmVideoTimeline: NSView {
    var value = 0.0 { didSet { needsDisplay = true; updateAccessibilityValue() } }
    var maximum = 1.0 { didSet { needsDisplay = true; updateAccessibilityValue() } }
    var onChange: ((Double) -> Void)?
    static let knobSize: CGFloat = 9
    private var inset: CGFloat { Self.knobSize / 2 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let width = max(1, bounds.width - inset * 2)
        let lineY = (bounds.midY - 0.5).rounded()
        InspectInk.lineStrong.setFill()
        NSRect(x: inset, y: lineY, width: width, height: 1).fill()
        let fraction = maximum > 0 ? min(1, max(0, value / maximum)) : 0
        InspectInk.text1.setFill()
        NSRect(x: inset, y: lineY, width: width * fraction, height: 1).fill()
        let knob = Self.knobSize
        NSBezierPath(ovalIn: NSRect(x: inset + width * fraction - knob / 2, y: bounds.midY - knob / 2,
                                    width: knob, height: knob)).fill()
    }

    override func mouseDown(with event: NSEvent) { update(event) }
    override func mouseDragged(with event: NSEvent) { update(event) }
    private func update(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let fraction = min(1, max(0, (x - inset) / max(1, bounds.width - inset * 2)))
        onChange?(fraction * maximum)
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue(maximum > 0 ? min(1, max(0, value / maximum)) : 0)
    }
}

/// A transparent group for the Shizuka titlebar controls and the transport
/// row. Only its controls take clicks; empty space falls through to the
/// titlebar drag region or the video beneath.
final class VideoPlaybackBar: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// A timecode drawn into its exact Figma text frame (mono 11), without
/// NSTextField cell insets or baselines.
final class VideoTimeLabel: NSView {
    var stringValue: String { didSet { needsDisplay = true; setAccessibilityValue(stringValue) } }
    var textColor = InspectInk.text2 { didSet { needsDisplay = true } }
    var alignment: NSTextAlignment = .left { didSet { needsDisplay = true } }
    static let font = PanelStyle.monoFont(ofSize: 11)

    init(_ value: String) {
        stringValue = value
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityValue(value)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var preferredWidth: CGFloat { InspectText.width(stringValue, font: Self.font) }

    override func draw(_ dirtyRect: NSRect) {
        InspectText.draw(stringValue, in: bounds, font: Self.font, color: textColor,
                         align: alignment, truncation: .byClipping)
    }
}

/// Figma `27 · Video Compare` pane caption: "A · name" (13 pt medium) with the
/// pane's sound state on the right (12 pt text/3), and the mono metadata
/// (11 pt text/3) 26 pt below the top of the name row.
final class VideoCompareCaption: NSView {
    private var letter = ""
    private var name = ""
    private var soundState = ""
    private var meta = ""
    static let height: CGFloat = 40
    private static let nameFont = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
    private static let stateFont = PanelStyle.inspectFont(ofSize: 12)
    private static let metaFont = PanelStyle.monoFont(ofSize: 11)

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(letter: String, name: String, soundState: String, meta: String) {
        guard letter != self.letter || name != self.name || soundState != self.soundState || meta != self.meta else { return }
        self.letter = letter
        self.name = name
        self.soundState = soundState
        self.meta = meta
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel([letter, name, soundState, meta].filter { !$0.isEmpty }.joined(separator: ", "))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let stateWidth = soundState.isEmpty ? 0 : InspectText.width(soundState, font: Self.stateFont)
        if stateWidth > 0 {
            InspectText.draw(soundState, in: NSRect(x: bounds.width - stateWidth, y: 2.5, width: stateWidth, height: 15),
                             font: Self.stateFont, color: InspectInk.text3)
        }
        let nameLimit = max(0, bounds.width - (stateWidth > 0 ? stateWidth + 10 : 0))
        InspectText.draw("\(letter) · \(name)", in: NSRect(x: 0, y: 2, width: nameLimit, height: 16),
                         font: Self.nameFont, color: InspectInk.text1, truncation: .byTruncatingMiddle)
        InspectText.draw(meta, in: NSRect(x: 0, y: 26, width: bounds.width, height: 14),
                         font: Self.metaFont, color: InspectInk.text3)
    }
}
