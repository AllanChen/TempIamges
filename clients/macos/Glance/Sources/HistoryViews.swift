import AppKit

// Views for the Preview History window, built from the Figma
// "Preview History Redesign" board. Everything is flipped (top-left origin) so
// the numbers below are the board's own coordinates.

// MARK: - Model

/// One row of history: the media, when it was previewed, and whether a Widget
/// produced it (those carry a "Result" pill).
struct HistoryEntry {
    let info: MediaInfo
    let timestamp: Date
    let isResult: Bool
    /// The value HistoryManager stores for this item (used to remove it).
    let storedValue: String
}

enum HistoryFilter: CaseIterable {
    case all, images, videos, documents

    var title: String {
        switch self {
        case .all: return "All".localized
        case .images: return "Images".localized
        case .videos: return "Videos".localized
        case .documents: return "Documents".localized
        }
    }

    func matches(_ info: MediaInfo) -> Bool {
        switch self {
        case .all: return true
        case .images: return info.kind == .image
        case .videos: return info.kind == .video
        case .documents: return info.kind != .image && info.kind != .video
        }
    }
}

// MARK: - Style

enum HistoryStyle {
    static func hex(_ value: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
    static let background = hex(0x0B0C0F)
    static let field = hex(0x14151A)
    static let chipActiveFill = hex(0x34251F, alpha: 0.96)
    static let overlayFill = hex(0x161719)
    static let hairline = NSColor.white.withAlphaComponent(0.07)
    static let text = PanelStyle.textPrimary
    static let secondary = PanelStyle.textSecondary
    static let muted = PanelStyle.textTertiary
    static let accent = PanelStyle.warmCue
    static let danger = PanelStyle.failure

    /// A bundled template icon tinted to `color`.
    static func icon(_ name: String, color: NSColor, size: CGFloat) -> NSImage? {
        guard let base = NSImage(named: name) else { return nil }
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    static func drawIcon(_ name: String, color: NSColor, in rect: CGRect) {
        icon(name, color: color, size: rect.width)?
            .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    static func attributes(size: CGFloat, weight: NSFont.Weight, color: NSColor,
                           align: NSTextAlignment = .left,
                           truncation: NSLineBreakMode = .byTruncatingTail) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = truncation
        return [.font: PanelStyle.inspectFont(ofSize: size, weight: weight),
                .foregroundColor: color, .paragraphStyle: style]
    }

    @discardableResult
    static func draw(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
                     color: NSColor, align: NSTextAlignment = .left,
                     truncation: NSLineBreakMode = .byTruncatingTail) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: attributes(size: size, weight: weight, color: color, align: align, truncation: truncation))
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        return attributed.size().width
    }

    static func width(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: [.font: PanelStyle.inspectFont(ofSize: size, weight: weight)]).size().width)
    }
}

// MARK: - Title bar

/// Window drag region with the centred title and subtitle (13 / 11 pt).
final class HistoryTitlebar: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var subtitle = "" { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        HistoryStyle.draw(title, in: CGRect(x: 100, y: 12, width: bounds.width - 200, height: 16), size: 13,
                          weight: .semibold, color: HistoryStyle.text, align: .center)
        HistoryStyle.draw(subtitle, in: CGRect(x: 100, y: 31, width: bounds.width - 200, height: 14), size: 11,
                          color: HistoryStyle.muted, align: .center)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
}

// MARK: - Search

final class HistoryTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}

/// 320 × 40 search field: icon, text, and either a ⌘F hint or a clear button.
final class HistorySearchBox: NSView, NSTextFieldDelegate {
    let field = HistoryTextField()
    var onChange: (() -> Void)?
    private var focused = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    var query: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = PanelStyle.inspectFont(ofSize: 13)
        field.textColor = HistoryStyle.text
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.onFocusChange = { [weak self] in self?.focused = $0 }
        addSubview(field)
        updatePlaceholder()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func updatePlaceholder() {
        field.placeholderAttributedString = NSAttributedString(
            string: "Search filename".localized,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 13), .foregroundColor: HistoryStyle.muted])
    }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func clear() {
        field.stringValue = ""
        needsDisplay = true
        onChange?()
    }

    private var clearRect: CGRect { CGRect(x: bounds.width - 12 - 20, y: 10, width: 20, height: 20) }

    override func layout() {
        super.layout()
        field.frame = CGRect(x: 40, y: 11, width: bounds.width - 40 - 44, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        HistoryStyle.field.setFill(); path.fill()
        (focused ? HistoryStyle.accent.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.10)).setStroke()
        path.lineWidth = 1; path.stroke()
        HistoryStyle.drawIcon("HistorySearch", color: focused ? HistoryStyle.accent : HistoryStyle.muted,
                              in: CGRect(x: 13, y: 11, width: 18, height: 18))
        if field.stringValue.isEmpty {
            let kbd = CGRect(x: bounds.width - 12 - 34, y: 9, width: 34, height: 22)
            NSColor.white.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: kbd, xRadius: 6, yRadius: 6).fill()
            HistoryStyle.draw("⌘F", in: CGRect(x: kbd.minX, y: kbd.minY + 4, width: kbd.width, height: 14), size: 11,
                              weight: .medium, color: HistoryStyle.muted, align: .center)
        } else {
            NSColor.white.withAlphaComponent(0.10).setFill()
            NSBezierPath(ovalIn: clearRect).fill()
            HistoryStyle.drawIcon("HistoryClose", color: HistoryStyle.secondary,
                                  in: CGRect(x: clearRect.minX + 4, y: clearRect.minY + 4, width: 12, height: 12))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !field.stringValue.isEmpty, clearRect.insetBy(dx: -4, dy: -4).contains(point) { clear(); return }
        focus()
    }

    func controlTextDidChange(_ obj: Notification) {
        needsDisplay = true
        onChange?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if field.stringValue.isEmpty { window?.makeFirstResponder(nil) } else { clear() }
        return true
    }
}

// MARK: - Filter chips and clear button

final class HistoryChipView: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var count = 0 { didSet { needsDisplay = true } }
    var isActive = false { didSet { needsDisplay = true } }
    var isDimmed = false { didSet { alphaValue = isDimmed ? 0.45 : 1 } }
    var onClick: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    var fittingWidth: CGFloat {
        14 + HistoryStyle.width(title, size: 12, weight: isActive ? .semibold : .medium) + 7
            + HistoryStyle.width(String(count), size: 12) + 14
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { if !isDimmed { onClick?() } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        if isActive {
            HistoryStyle.chipActiveFill.setFill()
        } else {
            NSColor.white.withAlphaComponent(hovering && !isDimmed ? 0.09 : 0.05).setFill()
        }
        path.fill()
        (isActive ? HistoryStyle.accent.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.08)).setStroke()
        path.lineWidth = 1; path.stroke()
        let labelWeight: NSFont.Weight = isActive ? .semibold : .medium
        let labelWidth = HistoryStyle.width(title, size: 12, weight: labelWeight)
        HistoryStyle.draw(title, in: CGRect(x: 14, y: 8, width: labelWidth + 2, height: 16), size: 12, weight: labelWeight,
                          color: isActive ? HistoryStyle.accent : HistoryStyle.secondary)
        HistoryStyle.draw(String(count), in: CGRect(x: 14 + labelWidth + 7, y: 8, width: 60, height: 16), size: 12,
                          color: isActive ? HistoryStyle.accent : HistoryStyle.muted)
    }
}

/// Quiet danger pill, 132 × 32.
final class HistoryClearButton: NSView {
    var onClick: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        if hovering { HistoryStyle.danger.withAlphaComponent(0.08).setFill(); path.fill() }
        HistoryStyle.danger.withAlphaComponent(0.32).setStroke()
        path.lineWidth = 1; path.stroke()
        HistoryStyle.drawIcon("HistoryClear", color: HistoryStyle.danger, in: CGRect(x: 12, y: 8, width: 16, height: 16))
        HistoryStyle.draw("Clear History".localized, in: CGRect(x: 34, y: 8, width: bounds.width - 40, height: 16), size: 12,
                          weight: .medium, color: HistoryStyle.danger)
    }
}

// MARK: - Section header

/// "Today  5 ────────" — title 15 semibold, count 12, hairline to the margin.
final class HistorySectionHeader: NSView {
    private let title: String
    private let count: Int
    override var isFlipped: Bool { true }

    init(title: String, count: Int) {
        self.title = title
        self.count = count
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let titleWidth = HistoryStyle.width(title, size: 15, weight: .semibold)
        HistoryStyle.draw(title, in: CGRect(x: 0, y: 0, width: min(titleWidth + 2, bounds.width), height: 20), size: 15,
                          weight: .semibold, color: HistoryStyle.text)
        let countX = titleWidth + 10
        let countText = String(count)
        let countWidth = HistoryStyle.width(countText, size: 12)
        HistoryStyle.draw(countText, in: CGRect(x: countX, y: 2, width: countWidth + 2, height: 16), size: 12,
                          color: HistoryStyle.muted)
        let lineX = countX + countWidth + 16
        if lineX < bounds.width {
            HistoryStyle.hairline.setFill()
            CGRect(x: lineX, y: 10, width: bounds.width - lineX, height: 1).fill()
        }
    }
}

// MARK: - Card

/// Round 30 pt hover action on a thumbnail (Reveal in Finder / Remove).
final class HistoryActionButton: NSView {
    var onClick: (() -> Void)?
    private let iconName: String
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(icon: String, tooltip: String) {
        iconName = icon
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        toolTip = tooltip
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        HistoryStyle.overlayFill.withAlphaComponent(hovering ? 0.96 : 0.84).setFill(); circle.fill()
        NSColor.white.withAlphaComponent(hovering ? 0.28 : 0.16).setStroke()
        circle.lineWidth = 1; circle.stroke()
        HistoryStyle.drawIcon(iconName, color: HistoryStyle.hex(0xF3F3F3), in: CGRect(x: 7, y: 7, width: 16, height: 16))
    }
}

/// Everything painted over the thumbnail: document tile, video badges, the
/// Result pill, load state, and the hover veil.
private final class HistoryThumbOverlay: NSView {
    enum State { case loading, loaded, failed, document }
    var state = State.loading { didSet { needsDisplay = true } }
    var isVideo = false { didSet { needsDisplay = true } }
    var isResult = false { didSet { needsDisplay = true } }
    var hovering = false { didSet { needsDisplay = true } }
    var extensionLabel = "" { didSet { needsDisplay = true } }
    var duration: String? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        switch state {
        case .document:
            let top = (h - 88) / 2 + 2
            let tile = CGRect(x: (w - 64) / 2, y: top, width: 64, height: 64)
            HistoryStyle.hex(0x202126).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 18, yRadius: 18).fill()
            NSColor.white.withAlphaComponent(0.08).setStroke()
            let outline = NSBezierPath(roundedRect: tile.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
            outline.lineWidth = 1; outline.stroke()
            HistoryStyle.drawIcon("HistoryFile", color: HistoryStyle.secondary,
                                  in: CGRect(x: tile.minX + 16, y: tile.minY + 16, width: 32, height: 32))
            HistoryStyle.draw(extensionLabel, in: CGRect(x: 0, y: tile.maxY + 10, width: w, height: 14), size: 11,
                              weight: .semibold, color: HistoryStyle.muted, align: .center)
        case .loading:
            if !isVideo {
                HistoryStyle.draw("Loading…".localized, in: CGRect(x: 0, y: h / 2 - 8, width: w, height: 16), size: 11,
                                  color: HistoryStyle.muted, align: .center)
            }
        case .failed:
            HistoryStyle.draw("Failed to load".localized, in: CGRect(x: 0, y: h / 2 - 8, width: w, height: 16), size: 11,
                              color: HistoryStyle.danger, align: .center)
        case .loaded:
            break
        }
        if isVideo {
            NSColor.black.withAlphaComponent(0.18).setFill()
            bounds.fill()
            let badge = CGRect(x: (w - 40) / 2, y: (h - 40) / 2, width: 40, height: 40)
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(ovalIn: badge).fill()
            NSColor.white.withAlphaComponent(0.28).setStroke()
            let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1; ring.stroke()
            HistoryStyle.drawIcon("HistoryPlay", color: HistoryStyle.hex(0xF3F3F3),
                                  in: CGRect(x: badge.minX + 11, y: badge.minY + 11, width: 18, height: 18))
            if let duration {
                let pillW = max(46, HistoryStyle.width(duration, size: 11, weight: .medium) + 16)
                let pill = CGRect(x: w - 10 - pillW, y: h - 10 - 20, width: pillW, height: 20)
                NSColor.black.withAlphaComponent(0.62).setFill()
                NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
                HistoryStyle.draw(duration, in: CGRect(x: pill.minX, y: pill.minY + 3, width: pill.width, height: 14), size: 11,
                                  weight: .medium, color: HistoryStyle.hex(0xF3F3F3), align: .center)
            }
        }
        if isResult {
            let label = "Result".localized
            let pillW = max(58, 22 + HistoryStyle.width(label, size: 11, weight: .semibold) + 8)
            let pill = CGRect(x: 10, y: 10, width: pillW, height: 22)
            HistoryStyle.overlayFill.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11).fill()
            HistoryStyle.accent.withAlphaComponent(0.5).setStroke()
            let outline = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
            outline.lineWidth = 1; outline.stroke()
            HistoryStyle.accent.setFill()
            NSBezierPath(ovalIn: CGRect(x: pill.minX + 10, y: pill.minY + 8, width: 6, height: 6)).fill()
            HistoryStyle.draw(label, in: CGRect(x: pill.minX + 22, y: pill.minY + 4, width: pillW - 24, height: 14), size: 11,
                              weight: .semibold, color: HistoryStyle.accent)
        }
        if hovering {
            NSColor.white.withAlphaComponent(0.05).setFill()
            bounds.fill()
        }
    }
}

/// Media-first card: a clean thumbnail with the name and metadata underneath.
/// Hovering lightens the thumbnail, lifts it with a shadow and reveals the
/// Reveal in Finder / Remove actions.
final class HistoryCardView: NSView {
    static let metaBlock: CGFloat = 52
    static func height(forWidth width: CGFloat) -> CGFloat { thumbHeight(forWidth: width) + metaBlock }
    static func thumbHeight(forWidth width: CGFloat) -> CGFloat { (width * 188 / 278).rounded() }

    var onOpen: (() -> Void)?
    var onReveal: (() -> Void)?
    var onRemove: (() -> Void)?

    let entry: HistoryEntry
    private let highlight: String
    private var metaText: String

    private let shadowLayer = CALayer()
    private let thumb = NSView()
    private let imageHost = NSView()
    private let overlay = HistoryThumbOverlay()
    private let revealButton = HistoryActionButton(icon: "HistoryFolder", tooltip: "Reveal in Finder".localized)
    private let removeButton = HistoryActionButton(icon: "HistoryClose", tooltip: "Remove from History".localized)

    override var isFlipped: Bool { true }

    init(entry: HistoryEntry, highlight: String, meta: String) {
        self.entry = entry
        self.highlight = highlight
        self.metaText = meta
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        shadowLayer.backgroundColor = HistoryStyle.field.cgColor
        shadowLayer.cornerRadius = 12
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0
        shadowLayer.shadowRadius = 12
        shadowLayer.shadowOffset = CGSize(width: 0, height: -10)
        layer?.insertSublayer(shadowLayer, at: 0)

        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 12
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = HistoryStyle.field.cgColor
        thumb.layer?.borderWidth = 1
        thumb.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        addSubview(thumb)

        imageHost.wantsLayer = true
        imageHost.layer?.contentsGravity = .resizeAspectFill
        imageHost.layer?.masksToBounds = true
        thumb.addSubview(imageHost)
        thumb.addSubview(overlay)

        overlay.isVideo = entry.info.kind == .video
        overlay.isResult = entry.isResult
        overlay.extensionLabel = Self.documentLabel(for: entry.info)

        revealButton.onClick = { [weak self] in self?.onReveal?() }
        removeButton.onClick = { [weak self] in self?.onRemove?() }
        revealButton.isHidden = true
        removeButton.isHidden = true
        thumb.addSubview(revealButton)
        thumb.addSubview(removeButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func documentLabel(for info: MediaInfo) -> String {
        switch info.kind {
        case .folder: return "FOLDER"
        case .webPage: return "WEB"
        default:
            let ext = info.formatName
            return ext.isEmpty ? "FILE" : ext
        }
    }

    // MARK: State

    func setThumbnail(_ image: CGImage) {
        imageHost.layer?.contents = image
        overlay.state = .loaded
    }
    func setFailed() { overlay.state = .failed }
    func setDocument() { overlay.state = .document }
    func setDuration(_ text: String) { overlay.duration = text }
    func setMeta(_ text: String) { metaText = text; needsDisplay = true }

    // MARK: Layout

    override func layout() {
        super.layout()
        let thumbH = Self.thumbHeight(forWidth: bounds.width)
        let frame = CGRect(x: 0, y: 0, width: bounds.width, height: thumbH)
        thumb.frame = frame
        imageHost.frame = thumb.bounds
        overlay.frame = thumb.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = frame
        CATransaction.commit()
        let w = bounds.width
        removeButton.frame = CGRect(x: w - 10 - 30, y: 10, width: 30, height: 30)
        revealButton.frame = CGRect(x: w - 10 - 68, y: 10, width: 30, height: 30)
    }

    // MARK: Hover

    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            overlay.hovering = hovering
            removeButton.isHidden = !hovering
            revealButton.isHidden = !hovering || !entry.info.isLocal
            thumb.layer?.borderWidth = hovering ? 1.5 : 1
            thumb.layer?.borderColor = NSColor.white.withAlphaComponent(hovering ? 0.38 : 0.08).cgColor
            shadowLayer.shadowOpacity = hovering ? 0.45 : 0
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onOpen?() }
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: Text under the thumbnail

    override func draw(_ dirtyRect: NSRect) {
        let thumbH = Self.thumbHeight(forWidth: bounds.width)
        let textWidth = bounds.width - 4
        let name = entry.info.filename
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        let normal: [NSAttributedString.Key: Any] = [
            .font: PanelStyle.inspectFont(ofSize: 13, weight: .medium), .foregroundColor: HistoryStyle.text, .paragraphStyle: style]
        let attributed = NSMutableAttributedString(string: name, attributes: normal)
        if !highlight.isEmpty, let range = name.range(of: highlight, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed.addAttributes([.font: PanelStyle.inspectFont(ofSize: 13, weight: .semibold),
                                      .foregroundColor: HistoryStyle.accent], range: NSRange(range, in: name))
        }
        attributed.draw(with: CGRect(x: 2, y: thumbH + 10, width: textWidth, height: 16),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        HistoryStyle.draw(metaText, in: CGRect(x: 2, y: thumbH + 30, width: textWidth, height: 14), size: 11,
                          color: HistoryStyle.muted)
    }
}

// MARK: - Empty state

/// Shown when there is no history yet, or a search / filter finds nothing.
final class HistoryEmptyView: NSView {
    private var icon = "HistoryFocus"
    private var heading = ""
    private var detail = ""
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(icon: String, heading: String, detail: String) {
        self.icon = icon; self.heading = heading; self.detail = detail
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let top = max(40, bounds.height / 2 - 120)
        let tile = CGRect(x: (bounds.width - 96) / 2, y: top, width: 96, height: 96)
        HistoryStyle.field.setFill()
        NSBezierPath(roundedRect: tile, xRadius: 28, yRadius: 28).fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        let outline = NSBezierPath(roundedRect: tile.insetBy(dx: 0.5, dy: 0.5), xRadius: 28, yRadius: 28)
        outline.lineWidth = 1; outline.stroke()
        HistoryStyle.drawIcon(icon, color: HistoryStyle.muted, in: CGRect(x: tile.minX + 28, y: tile.minY + 28, width: 40, height: 40))
        HistoryStyle.draw(heading, in: CGRect(x: 0, y: tile.maxY + 28, width: bounds.width, height: 26), size: 20,
                          weight: .semibold, color: HistoryStyle.text, align: .center)
        HistoryStyle.draw(detail, in: CGRect(x: (bounds.width - 460) / 2, y: tile.maxY + 64, width: 460, height: 44), size: 13,
                          color: HistoryStyle.secondary, align: .center, truncation: .byWordWrapping)
    }
}

/// Bottom fade that hints the list keeps scrolling.
final class HistoryFadeView: NSView {
    private let gradient = CAGradientLayer()
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.colors = [HistoryStyle.background.withAlphaComponent(0).cgColor, HistoryStyle.background.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)   // view is not flipped: y 1 is the top
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(gradient)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
}
