import AppKit

/// Error notice for moments with no window to attach to (selection and
/// hotkey failures). Same glass toast as everywhere else, placed by the cursor.
class ErrorTooltip: NSPanel {
    private let content = ToastPanelContent()
    private let offset = CGPoint(x: 20, y: -20)
    private let autoHideDelay: TimeInterval = 3.0
    private var autoHideWorkItem: DispatchWorkItem?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(message: String, at mouseLocation: NSPoint) {
        let size = content.apply(kind: .error, title: message, detail: nil, maxWidth: 420)
        let frame = ScreenManager.shared.adjustedFrame(for: size, at: mouseLocation, offset: offset)
        setFrame(frame, display: true)
        invalidateShadow()

        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.animator().alphaValue = 1
        }

        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        autoHideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        autoHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay, execute: item)
    }

    func hide() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}
