import AppKit

/// Short centered acknowledgement for successful save/export operations.
/// A child panel is used instead of a canvas subview so layer-backed image,
/// WebKit, and AV surfaces can never render above it.
final class InspectToastWindow: NSPanel {
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 156, height: 42),
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
        let frost = PanelStyle.makeFrostedBase(cornerRadius: 10)
        contentView = frost
        label.font = PanelStyle.label
        label.textColor = PanelStyle.textPrimary
        label.alignment = .center
        label.lineBreakMode = .byCharWrapping
        label.maximumNumberOfLines = 0
        frost.addSubview(label)
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(message: String, over parentWindow: NSWindow) {
        hideWorkItem?.cancel()
        let parts = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3
        let styled = NSMutableAttributedString(
            string: String(parts.first ?? ""),
            attributes: [.font: PanelStyle.label,
                         .foregroundColor: PanelStyle.textPrimary,
                         .paragraphStyle: paragraph])
        if parts.count > 1 {
            styled.append(NSAttributedString(
                string: "\n" + String(parts[1]),
                attributes: [.font: PanelStyle.caption,
                             .foregroundColor: PanelStyle.textSecondary,
                             .paragraphStyle: paragraph]))
        }
        label.attributedStringValue = styled
        let maxWidth = min(620, max(240, parentWindow.frame.width - 80))
        let textBounds = styled.boundingRect(
            with: NSSize(width: maxWidth - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = NSSize(width: min(maxWidth, max(156, ceil(textBounds.width) + 32)),
                          height: max(42, ceil(textBounds.height) + 20))
        label.frame = NSRect(origin: .zero, size: size).insetBy(dx: 12, dy: 10)
        let target = NSRect(x: parentWindow.frame.midX - size.width / 2,
                            y: parentWindow.frame.midY - size.height / 2,
                            width: size.width, height: size.height)
        if parent !== parentWindow {
            if let parent { parent.removeChildWindow(self) }
            parentWindow.addChildWindow(self, ordered: .above)
        }
        setFrame(target, display: true)
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 1
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
        let delay: TimeInterval = parts.count > 1 ? 2.5 : 1.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
