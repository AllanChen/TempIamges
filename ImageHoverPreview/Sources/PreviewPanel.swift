import AppKit

class PreviewPanel: NSPanel {
    // Place the panel just below the anchor point (top-left of preview is
    // 8px below anchor.y; left edge aligned with anchor.x).
    private let offset = CGPoint(x: 0, y: 8)
    private let spacing: CGFloat = 8

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setupPanel()
        contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func showImage(_ image: NSImage, at mouseLocation: NSPoint) {
        showImages([image], at: mouseLocation)
    }

    func showImages(_ images: [NSImage], at mouseLocation: NSPoint) {
        guard !images.isEmpty else {
            hidePanel()
            return
        }

        let maxSize = Preferences.shared.maxPreviewSize

        let sizes: [NSSize] = images.map { img in
            let w = img.size.width
            let h = img.size.height
            guard w > 0, h > 0 else { return NSSize(width: 100, height: 100) }
            var dw: CGFloat
            var dh: CGFloat
            if w >= h {
                dw = min(w, maxSize)
                dh = dw * (h / w)
            } else {
                dh = min(h, maxSize)
                dw = dh * (w / h)
            }
            return NSSize(width: max(100, dw), height: max(100, dh))
        }

        let totalWidth = sizes.map { $0.width }.reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1))
        let maxHeight = sizes.map { $0.height }.max() ?? 100
        let panelSize = NSSize(width: totalWidth, height: maxHeight)
        let frame = ScreenManager.shared.adjustedFrame(for: panelSize, at: mouseLocation, offset: offset)

        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        var x: CGFloat = 0
        for (img, size) in zip(images, sizes) {
            let y = (maxHeight - size.height) / 2
            let view = NSImageView(frame: NSRect(x: x, y: y, width: size.width, height: size.height))
            view.imageScaling = .scaleProportionallyUpOrDown
            view.wantsLayer = true
            view.layer?.cornerRadius = 12
            view.layer?.masksToBounds = true
            view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.1).cgColor
            view.image = img
            container.addSubview(view)
            x += size.width + spacing
        }
        contentView = container

        setFrame(frame, display: true)

        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func hidePanel() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }

    func clearImage() {
        contentView = NSView(frame: contentView?.frame ?? .zero)
    }
}
