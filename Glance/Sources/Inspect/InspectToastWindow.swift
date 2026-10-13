import AppKit

// The app's one notification style (Figma "Toast"): a glass capsule with a
// 32 pt icon badge, a 14 pt title and an optional 12 pt detail line.

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
        case .info: return PanelStyle.textPrimary
        case .error: return PanelStyle.failure
        }
    }
    var badgeAlpha: CGFloat { self == .info ? 0.10 : 0.16 }
}

private func toastFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    PanelStyle.inspectFont(ofSize: size, weight: weight)
}

private func drawToastText(_ string: String, in rect: CGRect, font: NSFont, color: NSColor,
                           truncation: NSLineBreakMode = .byTruncatingTail) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = truncation
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
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

private func drawToastBadge(kind: ToastKind, y: CGFloat) {
    let badge = CGRect(x: 14, y: y, width: 32, height: 32)
    kind.color.withAlphaComponent(kind.badgeAlpha).setFill()
    NSBezierPath(ovalIn: badge).fill()
    drawToastIcon(kind.iconName, color: kind.color, in: CGRect(x: badge.minX + 7, y: badge.minY + 7, width: 18, height: 18))
}

/// Title (+ optional detail) with the badge. 48 pt high, 64 with a detail.
final class ToastCardView: NSView {
    private var kind = ToastKind.info
    private var title = ""
    private var detail: String?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func fittingSize(title: String, detail: String?, maxWidth: CGFloat) -> NSSize {
        func width(_ s: String, _ font: NSFont) -> CGFloat {
            ceil(NSAttributedString(string: s, attributes: [.font: font]).size().width)
        }
        let text = max(width(title, toastFont(14, .semibold)), detail.map { width($0, toastFont(12, .regular)) } ?? 0)
        return NSSize(width: min(maxWidth, max(200, 14 + 32 + 12 + text + 20)), height: detail == nil ? 48 : 64)
    }

    func configure(kind: ToastKind, title: String, detail: String?) {
        self.kind = kind; self.title = title; self.detail = detail
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawToastBadge(kind: kind, y: (bounds.height - 32) / 2)
        let textWidth = bounds.width - 58 - 20
        if let detail {
            drawToastText(title, in: CGRect(x: 58, y: 12, width: textWidth, height: 18),
                          font: toastFont(14, .semibold), color: PanelStyle.textPrimary)
            drawToastText(detail, in: CGRect(x: 58, y: 33, width: textWidth, height: 16),
                          font: toastFont(12, .regular), color: PanelStyle.textSecondary, truncation: .byTruncatingMiddle)
        } else {
            drawToastText(title, in: CGRect(x: 58, y: 14, width: textWidth, height: 18),
                          font: toastFont(14, .semibold), color: PanelStyle.textPrimary)
        }
    }
}

/// Keyboard Shortcuts: key chips on the left, meaning on the right.
final class ToastShortcutsView: NSView {
    static let width: CGFloat = 440
    private static let rowHeight: CGFloat = 30
    private var rows: [(String, String)] {
        [("← →", "Previous / next"), ("0", "Fit to window"), ("1", "Actual size"), ("+  −", "Zoom"),
         ("Esc", "Exit compare / close"), ("⌥ click", "Compare with"), ("⌘C", "Copy"), ("⌘S", "Save"),
         ("⌘L  ⌘R", "Rotate"), ("⌘I", "Info"), ("⌘⇧X", "Capture")]
    }
    static var height: CGFloat { 14 + 32 + 12 + 11 * rowHeight + 14 }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        drawToastBadge(kind: .info, y: 14)
        drawToastText("Keyboard Shortcuts".localized, in: CGRect(x: 58, y: 21, width: 340, height: 18),
                      font: toastFont(14, .semibold), color: PanelStyle.textPrimary)
        for (index, row) in rows.enumerated() {
            let y = 14 + 32 + 12 + CGFloat(index) * Self.rowHeight
            let keyWidth = ceil(NSAttributedString(string: row.0, attributes: [.font: toastFont(11, .medium)]).size().width)
            let chip = CGRect(x: 14, y: y + 2, width: max(28, keyWidth + 16), height: 24)
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6).fill()
            NSColor.white.withAlphaComponent(0.08).setStroke()
            let outline = NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            outline.lineWidth = 1; outline.stroke()
            let centered = NSMutableParagraphStyle(); centered.alignment = .center
            NSAttributedString(string: row.0, attributes: [.font: toastFont(11, .medium),
                                                           .foregroundColor: PanelStyle.textPrimary,
                                                           .paragraphStyle: centered])
                .draw(with: CGRect(x: chip.minX, y: chip.minY + 5, width: chip.width, height: 14),
                      options: [.usesLineFragmentOrigin])
            drawToastText(row.1.localized, in: CGRect(x: 128, y: y + 6, width: 290, height: 16),
                          font: toastFont(12, .regular), color: PanelStyle.textSecondary)
        }
    }
}

/// Glass background shared by the toast window and the cursor error tooltip.
final class ToastPanelContent: NSVisualEffectView {
    let card = ToastCardView()
    let shortcuts = ToastShortcutsView()

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        let tint = CALayer()
        tint.backgroundColor = NSColor(srgbRed: 0x16 / 255, green: 0x17 / 255, blue: 0x19 / 255, alpha: 0.94).cgColor
        tint.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(tint)
        tint.frame = bounds
        for view in [card, shortcuts] {
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        shortcuts.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows a title/detail toast and returns the size the window should take.
    func apply(kind: ToastKind, title: String, detail: String?, maxWidth: CGFloat) -> NSSize {
        card.isHidden = false; shortcuts.isHidden = true
        card.configure(kind: kind, title: title, detail: detail)
        return ToastCardView.fittingSize(title: title, detail: detail, maxWidth: maxWidth)
    }

    func applyShortcuts() -> NSSize {
        card.isHidden = true; shortcuts.isHidden = false
        shortcuts.needsDisplay = true
        return NSSize(width: ToastShortcutsView.width, height: ToastShortcutsView.height)
    }
}

/// Short acknowledgement (saved, copied, failed) centred over a window.
/// A child panel is used instead of a canvas subview so layer-backed image,
/// WebKit, and AV surfaces can never render above it.
final class InspectToastWindow: NSPanel {
    private let content = ToastPanelContent()
    private var hideWorkItem: DispatchWorkItem?

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
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = content
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `message` is the title; text after the first newline becomes the detail
    /// line. A trailing "✓" is dropped (the badge says it). Without `kind`,
    /// "✓" messages are success ("copied" ones info) and anything else is info.
    func show(message: String, kind: ToastKind? = nil, over parentWindow: NSWindow, duration: TimeInterval? = nil) {
        let parts = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let rawTitle = parts.first ?? ""
        let title = rawTitle.replacingOccurrences(of: "✓", with: "").trimmingCharacters(in: .whitespaces)
        let detail = parts.count > 1 ? parts[1] : nil
        let resolved = kind ?? (rawTitle.contains("✓") ? (rawTitle.lowercased().contains("copied") || rawTitle.contains("复制") || rawTitle.contains("拷贝") ? .info : .success) : .info)
        let maxWidth = min(560, max(240, parentWindow.frame.width - 80))
        let size = content.apply(kind: resolved, title: title, detail: detail, maxWidth: maxWidth)
        present(size: size, over: parentWindow, duration: duration ?? (detail == nil ? 1.4 : 3))
    }

    func showShortcuts(over parentWindow: NSWindow, duration: TimeInterval = 7) {
        present(size: content.applyShortcuts(), over: parentWindow, duration: duration)
    }

    private func present(size: NSSize, over parentWindow: NSWindow, duration: TimeInterval) {
        hideWorkItem?.cancel()
        let target = NSRect(x: (parentWindow.frame.midX - size.width / 2).rounded(),
                            y: (parentWindow.frame.midY - size.height / 2).rounded(),
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
