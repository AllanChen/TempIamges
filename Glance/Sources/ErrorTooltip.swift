import AppKit

class ErrorTooltip: NSPanel {
    private let textField: NSTextField
    private let offset = CGPoint(x: 20, y: -20)

    init() {
        textField = NSTextField(labelWithString: "")

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setupPanel()
        setupTextField()
    }

    private func setupPanel() {
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
    }

    private func setupTextField() {
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.textColor = .white
        textField.wantsLayer = true
        textField.layer?.cornerRadius = 8
        textField.layer?.masksToBounds = true
        textField.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor

        contentView = textField
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(message: String, at mouseLocation: NSPoint) {
        let maxWidth: CGFloat = 300
        let constrainedSize = NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        let textSize = textField.cell?.cellSize(forBounds: NSRect(origin: .zero, size: constrainedSize)) ?? NSSize(width: 200, height: 30)

        let padding: CGFloat = 16
        let width = min(textSize.width + padding, maxWidth)
        let height = textSize.height + padding

        textField.stringValue = message
        textField.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let tooltipSize = NSSize(width: width, height: height)
        let frame = ScreenManager.shared.adjustedFrame(for: tooltipSize, at: mouseLocation, offset: offset)
        setFrame(frame, display: true)

        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}
