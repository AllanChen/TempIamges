import AppKit

// Views for the Preview History window, built from the Figma "静 Shizuka"
// frame "11 · Preview History". Everything is flipped (top-left origin) so the
// numbers below are the frame's own coordinates.

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
    static let background = PanelStyle.themed(hex(0x0B0C0F), PanelStyle.Washi.ink1)
    static let field = PanelStyle.themed(hex(0x14151A), PanelStyle.Washi.ink2)
    static let chipActiveFill = PanelStyle.themed(hex(0x34251F, alpha: 0.96), PanelStyle.Washi.ink4)
    static let overlayFill = PanelStyle.themed(hex(0x161719), PanelStyle.Washi.ink1)
    /// Glyph drawn on `overlayFill` buttons that float over thumbnails.
    static let overlayGlyph = PanelStyle.themed(hex(0xF3F3F3), PanelStyle.Washi.text1)
    static let hairline = PanelStyle.contrast.withAlphaComponent(0.07)
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

// MARK: - Text field (also used by Task Center)

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

// MARK: - Shizuka palette (Preview History only)

/// Preview History colours and text helpers on the Sumi / Washi ink scale.
/// `HistoryStyle` stays as-is because other windows share it.
enum HistoryShizuka {
    static let background = PanelStyle.surface
    static let field = PanelStyle.overlay
    static let badge = PanelStyle.canvas
    static let line = PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line)
    static let lineStrong = PanelStyle.themed(PanelStyle.Sumi.lineStrong, PanelStyle.Washi.lineStrong)
    static let text1 = PanelStyle.textPrimary
    static let text2 = PanelStyle.textSecondary
    static let text3 = PanelStyle.textTertiary
    static let text4 = PanelStyle.themed(PanelStyle.Sumi.text4, PanelStyle.Washi.text4)
    static let shu = PanelStyle.failure

    static func ui(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        PanelStyle.inspectFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat) -> NSFont { PanelStyle.monoFont(ofSize: size) }

    static func attributes(_ font: NSFont, _ color: NSColor, align: NSTextAlignment = .left,
                           truncation: NSLineBreakMode = .byTruncatingTail) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = truncation
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    static func draw(_ string: String, in rect: CGRect, font: NSFont, color: NSColor,
                     align: NSTextAlignment = .left, truncation: NSLineBreakMode = .byTruncatingTail) {
        NSAttributedString(string: string, attributes: attributes(font, color, align: align, truncation: truncation))
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    static func width(_ string: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
    }
}

// MARK: - Title bar

/// Window drag region with the centred 13 pt title (frame y 14).
final class HistoryTitlebar: NSView {
    var title = "" { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        HistoryShizuka.draw(title, in: CGRect(x: 100, y: 14, width: bounds.width - 200, height: 16),
                            font: HistoryShizuka.ui(13), color: HistoryShizuka.text2, align: .center)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
}

// MARK: - Search

/// 280 × 32 search field: icon at 11, text at 35, and either a ⌘F hint or a
/// clear button on the right.
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
        field.font = HistoryShizuka.ui(13)
        field.textColor = HistoryShizuka.text1
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
            attributes: [.font: HistoryShizuka.ui(13), .foregroundColor: HistoryShizuka.text3])
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

    private var clearRect: CGRect { CGRect(x: bounds.width - 8 - 16, y: 8, width: 16, height: 16) }

    override func layout() {
        super.layout()
        field.frame = CGRect(x: 35, y: 7, width: bounds.width - 35 - 36, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = PanelStyle.Radius.control
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        HistoryShizuka.field.setFill(); path.fill()
        (focused ? HistoryShizuka.text4 : HistoryShizuka.line).setStroke()
        path.lineWidth = 1; path.stroke()
        HistoryStyle.drawIcon("HistorySearch", color: focused ? HistoryShizuka.text2 : HistoryShizuka.text3,
                              in: CGRect(x: 11, y: 8, width: 16, height: 16))
        if field.stringValue.isEmpty {
            HistoryShizuka.draw("⌘F", in: CGRect(x: bounds.width - 10 - 40, y: 9.5, width: 40, height: 13),
                                font: HistoryShizuka.mono(10), color: HistoryShizuka.text4, align: .right)
        } else {
            PanelStyle.contrast.withAlphaComponent(0.10).setFill()
            NSBezierPath(ovalIn: clearRect).fill()
            HistoryStyle.drawIcon("HistoryClose", color: HistoryShizuka.text2,
                                  in: CGRect(x: clearRect.minX + 3, y: clearRect.minY + 3, width: 10, height: 10))
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

// MARK: - Filter tabs, count and clear button

/// Text tab: 12 pt label (selected text/1 medium, others text/3) followed by
/// its mono match count. The view spans the 32 pt toolbar for an easy target.
final class HistoryFilterTab: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var count = 0 { didSet { needsDisplay = true } }
    var isActive = false { didSet { needsDisplay = true } }
    var isDimmed = false { didSet { alphaValue = isDimmed ? 0.45 : 1 } }
    var onClick: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var labelFont: NSFont { HistoryShizuka.ui(12, isActive ? .medium : .regular) }
    private static let countGap: CGFloat = 4

    var fittingWidth: CGFloat {
        HistoryShizuka.width(title, font: labelFont) + Self.countGap
            + HistoryShizuka.width(String(count), font: HistoryShizuka.mono(10))
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
        let color = isActive ? HistoryShizuka.text1 : (hovering && !isDimmed ? HistoryShizuka.text2 : HistoryShizuka.text3)
        let labelWidth = HistoryShizuka.width(title, font: labelFont)
        HistoryShizuka.draw(title, in: CGRect(x: 0, y: 8.5, width: labelWidth + 1, height: 15), font: labelFont, color: color)
        HistoryShizuka.draw(String(count), in: CGRect(x: labelWidth + Self.countGap, y: 10, width: 40, height: 13),
                            font: HistoryShizuka.mono(10), color: HistoryShizuka.text4)
    }
}

/// Right-aligned 12 pt text/3 item count in the toolbar.
final class HistoryCountLabel: NSView {
    var text = "" { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        HistoryShizuka.draw(text, in: CGRect(x: 0, y: 8.5, width: bounds.width, height: 15),
                            font: HistoryShizuka.ui(12), color: HistoryShizuka.text3, align: .right)
    }
}

/// Quiet outline button, 32 pt high, 17 pt side padding, 13 pt medium label.
final class HistoryClearButton: NSView {
    var onClick: (() -> Void)?
    var title = "" { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private static let font = HistoryShizuka.ui(13, .medium)
    var fittingWidth: CGFloat { HistoryShizuka.width(title, font: Self.font) + 34 }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let radius = PanelStyle.Radius.control
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if hovering { PanelStyle.rowHover.setFill(); path.fill() }
        HistoryShizuka.lineStrong.setStroke()
        path.lineWidth = 1; path.stroke()
        HistoryShizuka.draw(title, in: CGRect(x: 0, y: 8, width: bounds.width, height: 16),
                            font: Self.font, color: HistoryShizuka.text1, align: .center)
    }
}

// MARK: - Section header

/// "Today  6" — 13 pt medium title, mono count in text/4. No rule: space groups.
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
        let font = HistoryShizuka.ui(13, .medium)
        let titleWidth = min(HistoryShizuka.width(title, font: font) + 1, bounds.width)
        HistoryShizuka.draw(title, in: CGRect(x: 0, y: 0, width: titleWidth, height: 16), font: font, color: HistoryShizuka.text1)
        HistoryShizuka.draw(String(count), in: CGRect(x: titleWidth + 7, y: 1.5, width: 60, height: 14),
                            font: HistoryShizuka.mono(11), color: HistoryShizuka.text4)
    }
}

// MARK: - Card

/// 24 pt hover action on a thumbnail (Reveal in Finder / Remove).
final class HistoryActionButton: NSView {
    var onClick: (() -> Void)?
    private let iconName: String
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(icon: String, tooltip: String) {
        iconName = icon
        super.init(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
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
        let radius = PanelStyle.Radius.control
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        HistoryShizuka.badge.withAlphaComponent(hovering ? 1 : 0.86).setFill(); box.fill()
        (hovering ? HistoryShizuka.lineStrong : HistoryShizuka.line).setStroke()
        box.lineWidth = 1; box.stroke()
        HistoryStyle.drawIcon(iconName, color: hovering ? HistoryShizuka.text1 : HistoryShizuka.text2,
                              in: CGRect(x: 5, y: 5, width: 14, height: 14))
    }
}

/// Everything painted over the thumbnail: document tile, video badge, the
/// Result mark, load state, and the hover veil.
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
            let icon = CGRect(x: ((w - 16) / 2).rounded(), y: ((h - 16) / 2).rounded(), width: 16, height: 16)
            HistoryStyle.drawIcon("HistoryFile", color: HistoryShizuka.text3, in: icon)
            HistoryShizuka.draw(extensionLabel, in: CGRect(x: 0, y: icon.maxY + 8, width: w, height: 13),
                                font: HistoryShizuka.mono(10), color: HistoryShizuka.text4, align: .center)
        case .loading:
            if !isVideo {
                HistoryShizuka.draw("Loading…".localized, in: CGRect(x: 0, y: h / 2 - 7.5, width: w, height: 15),
                                    font: HistoryShizuka.ui(11), color: HistoryShizuka.text3, align: .center)
            }
        case .failed:
            HistoryShizuka.draw("Failed to load".localized, in: CGRect(x: 0, y: h / 2 - 7.5, width: w, height: 15),
                                font: HistoryShizuka.ui(11), color: HistoryShizuka.shu, align: .center)
        case .loaded:
            break
        }
        if isVideo { drawVideoBadge(height: h) }
        if isResult { drawResultMark() }
        if hovering {
            PanelStyle.contrast.withAlphaComponent(0.05).setFill()
            bounds.fill()
        }
    }

    /// Bottom-left: play glyph plus the mono duration once it is known (8, h − 30, 56 × 19).
    private func drawVideoBadge(height h: CGFloat) {
        let font = HistoryShizuka.mono(10)
        let textWidth = duration.map { HistoryShizuka.width($0, font: font) } ?? 0
        let badgeW = duration == nil ? 22 : max(56, 20 + textWidth + 6)
        let badge = CGRect(x: 8, y: h - 11 - 19, width: badgeW, height: 19)
        let radius = PanelStyle.Radius.thumb
        HistoryShizuka.badge.setFill()
        NSBezierPath(roundedRect: badge, xRadius: radius, yRadius: radius).fill()
        HistoryStyle.drawIcon("HistoryPlay", color: HistoryShizuka.text1,
                              in: CGRect(x: badge.minX + 6, y: badge.minY + 4.5, width: 10, height: 10))
        if let duration {
            HistoryShizuka.draw(duration, in: CGRect(x: badge.minX + 20, y: badge.minY + 3, width: badgeW - 20, height: 13),
                                font: font, color: HistoryShizuka.text1)
        }
    }

    /// Top-left: a vermilion dot (the one accent) and "Result" on the same badge chrome.
    private func drawResultMark() {
        let font = HistoryShizuka.ui(10, .medium)
        let label = "Result".localized
        let badge = CGRect(x: 8, y: 8, width: 17 + HistoryShizuka.width(label, font: font) + 7, height: 19)
        let radius = PanelStyle.Radius.thumb
        HistoryShizuka.badge.setFill()
        NSBezierPath(roundedRect: badge, xRadius: radius, yRadius: radius).fill()
        HistoryShizuka.shu.setFill()
        NSBezierPath(ovalIn: CGRect(x: badge.minX + 7, y: badge.minY + 6.5, width: 6, height: 6)).fill()
        HistoryShizuka.draw(label, in: CGRect(x: badge.minX + 17, y: badge.minY + 3, width: badge.width - 17, height: 13),
                            font: font, color: HistoryShizuka.text1)
    }
}

/// Media-first item: a 4:3-ish thumbnail (204 × 147 in Figma) with the name
/// and a mono metadata line underneath. Hovering outlines the thumbnail and
/// reveals the Reveal in Finder / Remove actions.
final class HistoryCardView: NSView {
    /// 8 + name 15 + 8 + meta 13.
    static let metaBlock: CGFloat = 44
    static func height(forWidth width: CGFloat) -> CGFloat { thumbHeight(forWidth: width) + metaBlock }
    static func thumbHeight(forWidth width: CGFloat) -> CGFloat { (width * 147 / 204).rounded() }

    var onOpen: (() -> Void)?
    var onReveal: (() -> Void)?
    var onRemove: (() -> Void)?

    let entry: HistoryEntry
    private let highlight: String
    private var metaText: String
    private var hasImage = false

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

        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = PanelStyle.Radius.thumb
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = PanelStyle.resolvedCG(HistoryShizuka.field)
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
        updateBorder()
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
        hasImage = true
        updateBorder()
    }
    func setFailed() { overlay.state = .failed }
    func setDocument() { overlay.state = .document }
    func setDuration(_ text: String) { overlay.duration = text }
    func setMeta(_ text: String) { metaText = text; needsDisplay = true }

    /// Photos run edge to edge; placeholder tiles keep a hairline. Hover
    /// strengthens the line on both.
    private func updateBorder() {
        let showLine = hovering || !hasImage
        thumb.layer?.borderWidth = showLine ? 1 : 0
        thumb.layer?.borderColor = PanelStyle.resolvedCG(hovering ? HistoryShizuka.lineStrong : HistoryShizuka.line)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let w = bounds.width
        thumb.frame = CGRect(x: 0, y: 0, width: w, height: Self.thumbHeight(forWidth: w))
        imageHost.frame = thumb.bounds
        overlay.frame = thumb.bounds
        removeButton.frame = CGRect(x: w - 8 - 24, y: 8, width: 24, height: 24)
        revealButton.frame = CGRect(x: w - 8 - 24 - 4 - 24, y: 8, width: 24, height: 24)
    }

    // MARK: Hover

    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            overlay.hovering = hovering
            removeButton.isHidden = !hovering
            revealButton.isHidden = !hovering || !entry.info.isLocal
            updateBorder()
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
        let name = entry.info.filename
        let attributed = NSMutableAttributedString(
            string: name, attributes: HistoryShizuka.attributes(HistoryShizuka.ui(12), HistoryShizuka.text1, truncation: .byTruncatingMiddle))
        if !highlight.isEmpty, let range = name.range(of: highlight, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed.addAttributes([.font: HistoryShizuka.ui(12, .semibold),
                                      .backgroundColor: PanelStyle.contrast.withAlphaComponent(0.14)],
                                     range: NSRange(range, in: name))
        }
        attributed.draw(with: CGRect(x: 0, y: thumbH + 8, width: bounds.width, height: 15),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        HistoryShizuka.draw(metaText, in: CGRect(x: 0, y: thumbH + 31, width: bounds.width, height: 13),
                            font: HistoryShizuka.mono(10), color: HistoryShizuka.text3)
    }
}

// MARK: - Empty state

/// "No previews yet" / "No matches": 24 pt icon, Mincho title, one quiet
/// sentence (Figma "47 · Empty states"), centred in the list area.
final class HistoryEmptyView: NSView {
    private var icon = "ShizukaImage"
    private var heading = ""
    private var detail = ""
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private static let detailWidth: CGFloat = 254

    func configure(icon: String, heading: String, detail: String) {
        self.icon = icon; self.heading = heading; self.detail = detail
        needsDisplay = true
    }

    private var detailAttributes: [NSAttributedString.Key: Any] {
        var attributes = HistoryShizuka.attributes(HistoryShizuka.ui(13), HistoryShizuka.text3, align: .center, truncation: .byWordWrapping)
        if let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            style.minimumLineHeight = 19
            style.maximumLineHeight = 19
            attributes[.paragraphStyle] = style
        }
        return attributes
    }

    override func draw(_ dirtyRect: NSRect) {
        let detailText = NSAttributedString(string: detail, attributes: detailAttributes)
        let detailH = ceil(detailText.boundingRect(with: NSSize(width: Self.detailWidth, height: 400),
                                                   options: [.usesLineFragmentOrigin]).height)
        // icon 24, 26 to the title (10 + 6 + 10), title 28, 10, detail.
        let blockH = 24 + 26 + 28 + 10 + detailH
        let top = max(Space.top, ((bounds.height - blockH) / 2 - Space.lift).rounded())
        HistoryStyle.drawIcon(icon, color: HistoryShizuka.text3, in: CGRect(x: ((bounds.width - 24) / 2).rounded(), y: top, width: 24, height: 24))
        HistoryShizuka.draw(heading, in: CGRect(x: 0, y: top + 50, width: bounds.width, height: 28),
                            font: PanelStyle.titleFont(ofSize: 22), color: HistoryShizuka.text1, align: .center)
        detailText.draw(with: CGRect(x: ((bounds.width - Self.detailWidth) / 2).rounded(), y: top + 88,
                                     width: Self.detailWidth, height: detailH),
                        options: [.usesLineFragmentOrigin])
    }

    private enum Space {
        static let top = PanelStyle.Space.xxl
        /// Sit slightly above centre, as the toolbar already weights the top.
        static let lift = PanelStyle.Space.xl
    }
}

/// Bottom fade that hints the list keeps scrolling.
final class HistoryFadeView: NSView {
    private let gradient = CAGradientLayer()
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.colors = [PanelStyle.resolvedCG(HistoryShizuka.background.withAlphaComponent(0)),
                           PanelStyle.resolvedCG(HistoryShizuka.background)]
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
