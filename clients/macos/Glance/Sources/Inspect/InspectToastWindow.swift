import AppKit

// The app's one notification style (Figma `15 · Toasts & feedback`): an
// ink/3 capsule with a 16 pt icon, a 13 pt message and a mono detail.

enum ToastKind {
    case success, info, error

    var iconName: String {
        switch self {
        case .success: return "ToastCheck"
        case .info: return "ToastCopy"
        case .error: return "ToastWarning"
        }
    }
    var color: NSColor {
        switch self {
        case .success: return PanelStyle.success
        case .info: return PanelStyle.textSecondary
        case .error: return PanelStyle.failure
        }
    }
}

private func toastFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    PanelStyle.inspectFont(ofSize: size, weight: weight)
}

private func drawToastIcon(_ name: String, color: NSColor, in rect: CGRect) {
    guard let base = NSImage(named: name) else { return }
    let tinted = NSImage(size: rect.size, flipped: false) { bounds in
        base.draw(in: bounds)
        color.set()
        bounds.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

/// Message (+ optional detail). One line when it fits — icon, message and
/// mono detail side by side (10 pt gaps, padding 14 / 16 × 10); otherwise
/// the detail wraps below the message, and the toast stops growing at its maximum.
final class ToastCardView: NSView {
    private static let textInsetLeft: CGFloat = 40   // 14 + 16 icon + 10
    private static let textInsetRight: CGFloat = 16
    private static let minHeight: CGFloat = 38
    private static let detailGap: CGFloat = 4

    private var kind = ToastKind.info
    private var title = ""
    private var detail: String?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private static func titleAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        return [.font: toastFont(13, .regular), .foregroundColor: PanelStyle.textPrimary, .paragraphStyle: style]
    }
    /// Paths and URLs have no spaces, so the detail wraps by character.
    private static func detailAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byCharWrapping
        return [.font: PanelStyle.monoFont(ofSize: 11), .foregroundColor: PanelStyle.textTertiary, .paragraphStyle: style]
    }

    private static func height(of string: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: attributes)
            .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    private static func oneLine(_ s: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil(NSAttributedString(string: s, attributes: attributes).size().width)
    }

    private static func singleLineWidth(title: String, detail: String?) -> CGFloat {
        textInsetLeft + oneLine(title, titleAttributes())
            + (detail.map { 10 + oneLine($0, detailAttributes()) } ?? 0) + textInsetRight
    }

    /// Heights of the message and detail blocks for a stacked toast `width` wide.
    private static func blocks(title: String, detail: String?, width: CGFloat, maxHeight: CGFloat) -> (title: CGFloat, detail: CGFloat) {
        let textWidth = width - textInsetLeft - textInsetRight
        let room = max(16, maxHeight - 20)
        let titleH = min(height(of: title, attributes: titleAttributes(), width: textWidth), room)
        guard let detail else { return (titleH, 0) }
        let detailRoom = max(14, room - titleH - detailGap)
        return (titleH, min(height(of: detail, attributes: detailAttributes(), width: textWidth), detailRoom))
    }

    /// As wide as the text wants, never wider than `maxWidth`; as tall as the
    /// wrapped text needs, never taller than `maxHeight`.
    static func fittingSize(title: String, detail: String?, maxWidth: CGFloat, maxHeight: CGFloat) -> NSSize {
        let single = singleLineWidth(title: title, detail: detail)
        if single <= maxWidth { return NSSize(width: single, height: min(maxHeight, minHeight)) }
        let wanted = max(oneLine(title, titleAttributes()), detail.map { oneLine($0, detailAttributes()) } ?? 0)
        let width = min(maxWidth, textInsetLeft + wanted + textInsetRight)
        let heights = blocks(title: title, detail: detail, width: width, maxHeight: maxHeight)
        let content = heights.title + (detail == nil ? 0 : detailGap + heights.detail)
        return NSSize(width: width, height: min(maxHeight, max(minHeight, content + 20)))
    }

    func configure(kind: ToastKind, title: String, detail: String?) {
        self.kind = kind; self.title = title; self.detail = detail
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let textWidth = bounds.width - Self.textInsetLeft - Self.textInsetRight
        let titleWidth = Self.oneLine(title, Self.titleAttributes())
        if bounds.height <= Self.minHeight + 0.5, Self.singleLineWidth(title: title, detail: detail) <= bounds.width + 0.5 {
            // One line: the text frames sit 11 pt from the top of the 38 pt capsule.
            drawToastIcon(kind.iconName, color: kind.color, in: CGRect(x: 14, y: 11, width: 16, height: 16))
            NSAttributedString(string: title, attributes: Self.titleAttributes())
                .draw(with: CGRect(x: Self.textInsetLeft, y: 11, width: titleWidth, height: 16),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            if let detail {
                NSAttributedString(string: detail, attributes: Self.detailAttributes())
                    .draw(with: CGRect(x: Self.textInsetLeft + titleWidth + 10, y: 12,
                                       width: max(0, bounds.width - Self.textInsetLeft - titleWidth - 10 - Self.textInsetRight),
                                       height: 14),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }
            return
        }
        let heights = Self.blocks(title: title, detail: detail, width: bounds.width, maxHeight: bounds.height)
        let content = heights.title + (detail == nil ? 0 : Self.detailGap + heights.detail)
        let top = max(10, ((bounds.height - content) / 2).rounded())
        drawToastIcon(kind.iconName, color: kind.color, in: CGRect(x: 14, y: top, width: 16, height: 16))
        NSAttributedString(string: title, attributes: Self.titleAttributes())
            .draw(with: CGRect(x: Self.textInsetLeft, y: top, width: textWidth, height: heights.title),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        if let detail {
            NSAttributedString(string: detail, attributes: Self.detailAttributes())
                .draw(with: CGRect(x: Self.textInsetLeft, y: top + heights.title + Self.detailGap,
                                   width: textWidth, height: heights.detail),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}

/// Figma `25 · Shortcuts`: a Mincho title and rows of meaning (13 pt text/2)
/// with an ink/3 key chip (12 pt text/1) on the right, divided by line/hair.
final class ToastShortcutsView: NSView {
    static let width: CGFloat = 520
    private static let rowHeight: CGFloat = 33
    private var rows: [(String, String)] {
        [("← →", "Previous / next"), ("0", "Fit to window"), ("1", "Actual size"), ("+  −", "Zoom"),
         ("⌥-click", "Compare with"), ("Esc", "Exit compare / close"), ("⌘C", "Copy"), ("⌘S", "Save"),
         ("⌘L  ⌘R", "Rotate"), ("⌘I", "Info"), ("⌘⇧X", "Capture")]
    }
    /// Padding 28 top / 24 bottom, title 30, 16 pt gap, then the rows.
    static var height: CGFloat { 28 + 30 + 16 + 11 * rowHeight + 24 }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 32
        let width = bounds.width - inset * 2
        InspectText.draw("Keyboard Shortcuts".localized, in: CGRect(x: inset, y: 28, width: width, height: 30),
                         font: PanelStyle.titleFont(ofSize: 22), color: InspectInk.text1)
        let keyFont = toastFont(12, .regular)
        for (index, row) in rows.enumerated() {
            let y = 28 + 30 + 16 + CGFloat(index) * Self.rowHeight
            InspectText.draw(row.1.localized, in: CGRect(x: inset, y: y + 8, width: width - 120, height: 16),
                             font: toastFont(13, .regular), color: InspectInk.text2)
            let keyWidth = InspectText.width(row.0, font: keyFont)
            let chip = CGRect(x: bounds.width - inset - keyWidth - 14, y: y + 6.5, width: keyWidth + 14, height: 19)
            InspectInk.ink3.setFill()
            NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
            InspectText.draw(row.0, in: CGRect(x: chip.minX + 7, y: chip.minY + 2, width: keyWidth, height: 15),
                             font: keyFont, color: InspectInk.text1)
            InspectInk.line.setFill()
            NSRect(x: inset, y: y + Self.rowHeight - 1, width: width, height: 1).fill()
        }
    }
}

/// Plate shared by the toast window and the cursor error tooltip: ink/3 with a
/// line/strong edge for toasts (10 pt corners), ink/1 for the shortcuts sheet (12 pt).
final class ToastPanelContent: NSVisualEffectView {
    let card = ToastCardView()
    let shortcuts = ToastShortcutsView()
    private let tint = CALayer()

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        appearance = PanelStyle.vibrantAppearance
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
        layer?.addSublayer(tint)
        for view in [card, shortcuts] {
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        shortcuts.isHidden = true
        applyPlate(radius: 10, color: InspectInk.ink3.withAlphaComponent(0.96))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A behind-window material ignores the layer's corner radius and fills
    /// the whole borderless window; the mask clips both it and its shadow.
    private func applyPlate(radius: CGFloat, color: NSColor) {
        layer?.cornerRadius = radius
        maskImage = PanelStyle.roundedMask(radius: radius)
        tint.backgroundColor = PanelStyle.resolvedCG(color)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tint.frame = bounds
        CATransaction.commit()
    }

    /// Shows a title/detail toast and returns the size the window should take.
    func apply(kind: ToastKind, title: String, detail: String?, maxWidth: CGFloat, maxHeight: CGFloat) -> NSSize {
        card.isHidden = false; shortcuts.isHidden = true
        applyPlate(radius: 10, color: InspectInk.ink3.withAlphaComponent(0.96))
        card.configure(kind: kind, title: title, detail: detail)
        return ToastCardView.fittingSize(title: title, detail: detail, maxWidth: maxWidth, maxHeight: maxHeight)
    }

    func applyShortcuts() -> NSSize {
        card.isHidden = true; shortcuts.isHidden = false
        applyPlate(radius: PanelStyle.Radius.window, color: InspectInk.ink1)
        shortcuts.needsDisplay = true
        return NSSize(width: ToastShortcutsView.width, height: ToastShortcutsView.height)
    }
}

/// Short acknowledgement (saved, copied, failed) at the bottom centre of a
/// window (Figma: "One line. Bottom-centre of the window."); the shortcuts
/// sheet is centred.
/// A child panel is used instead of a canvas subview so layer-backed image,
/// WebKit, and AV surfaces can never render above it.
final class InspectToastWindow: NSPanel {
    private let content = ToastPanelContent()
    private var hideWorkItem: DispatchWorkItem?
    private var toastAction: (() -> Void)?
    /// Distance from the parent window's bottom edge to the toast. Windows with
    /// a bottom bar raise it above their controls.
    var bottomInset: CGFloat = PanelStyle.Space.xl
    private let actionButton = NSButton()
    @objc private func invokeAction() { let action = toastAction; toastAction = nil; orderOut(nil); action?() }
    func showAction(message: String, actionTitle: String, over parent: NSWindow, action: @escaping () -> Void) {
        actionButton.isHidden = true
        let bodySize = content.apply(kind: .info, title: message, detail: nil, maxWidth: max(160,parent.frame.width*0.5-64), maxHeight: max(48,parent.frame.height*0.5))
        present(size: NSSize(width: bodySize.width+64,height: bodySize.height),over:parent,duration:6)
        toastAction = action
        actionButton.title = actionTitle; actionButton.target = self; actionButton.action = #selector(invokeAction)
        actionButton.isBordered = false; actionButton.contentTintColor = InspectInk.text1
        actionButton.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        content.card.frame = NSRect(origin:.zero,size:bodySize)
        content.card.autoresizingMask = [.height]
        actionButton.frame = NSRect(x: bodySize.width, y: (bodySize.height-28)/2, width: 60, height: 28)
        content.addSubview(actionButton); actionButton.isHidden = false
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 48),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = PanelStyle.windowAppearance
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = content
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Hugs its text, up to half the window's width and height; longer text wraps.
    /// `message` is the title; text after the first newline becomes the detail
    /// line. A trailing "✓" is dropped (the badge says it). Without `kind`,
    /// "✓" messages are success ("copied" ones info) and anything else is info.
    func show(message: String, kind: ToastKind? = nil, over parentWindow: NSWindow, duration: TimeInterval? = nil) {
        actionButton.isHidden = true; toastAction = nil; content.card.autoresizingMask = [.width, .height]
        let parts = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let rawTitle = parts.first ?? ""
        let title = rawTitle.replacingOccurrences(of: "✓", with: "").trimmingCharacters(in: .whitespaces)
        let detail = parts.count > 1 ? parts[1] : nil
        let resolved = kind ?? (rawTitle.contains("✓") ? (rawTitle.lowercased().contains("copied") || rawTitle.contains("复制") || rawTitle.contains("拷贝") ? .info : .success) : .info)
        // Never more than half the window in either direction.
        let size = content.apply(kind: resolved, title: title, detail: detail,
                                 maxWidth: max(160, parentWindow.frame.width * 0.5),
                                 maxHeight: max(48, parentWindow.frame.height * 0.5))
        present(size: size, over: parentWindow, duration: duration ?? 3)
    }

    func showShortcuts(over parentWindow: NSWindow, duration: TimeInterval = 7) {
        present(size: content.applyShortcuts(), over: parentWindow, duration: duration, centered: true)
    }

    private func present(size: NSSize, over parentWindow: NSWindow, duration: TimeInterval, centered: Bool = false) {
        hideWorkItem?.cancel()
        let y = centered ? parentWindow.frame.midY - size.height / 2 : parentWindow.frame.minY + bottomInset
        let target = NSRect(x: (parentWindow.frame.midX - size.width / 2).rounded(), y: y.rounded(),
                            width: size.width, height: size.height)
        if parent !== parentWindow {
            if let parent { parent.removeChildWindow(self) }
            parentWindow.addChildWindow(self, ordered: .above)
        }
        // Fade in and rise 8 pt, unless the user asked for reduced motion.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var start = target
        if !reduceMotion { start.origin.y -= 8 }
        setFrame(start, display: true)
        alphaValue = 0
        orderFront(nil)
        invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
            if !reduceMotion { animator().setFrame(target, display: true) }
        }
        let item = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self?.animator().alphaValue = 0
            }, completionHandler: {
                guard let self else { return }
                self.parent?.removeChildWindow(self)
                self.orderOut(nil)
            })
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }
}
