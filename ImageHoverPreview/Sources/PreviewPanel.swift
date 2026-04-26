import AppKit

class PreviewPanel: NSPanel {
    private let imageView: NSImageView
    private let offset = CGPoint(x: 20, y: -20)

    init() {
        imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setupPanel()
        setupImageView()
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

    private func setupImageView() {
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.1).cgColor

        contentView = imageView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func showImage(_ image: NSImage, at mouseLocation: NSPoint) {
        let maxSize = Preferences.shared.maxPreviewSize
        let imageSize = image.size

        var panelWidth: CGFloat
        var panelHeight: CGFloat

        if imageSize.width > imageSize.height {
            panelWidth = min(imageSize.width, maxSize)
            panelHeight = panelWidth * (imageSize.height / imageSize.width)
        } else {
            panelHeight = min(imageSize.height, maxSize)
            panelWidth = panelHeight * (imageSize.width / imageSize.height)
        }

        panelWidth = max(panelWidth, 100)
        panelHeight = max(panelHeight, 100)

        let panelSize = NSSize(width: panelWidth, height: panelHeight)
        let frame = ScreenManager.shared.adjustedFrame(for: panelSize, at: mouseLocation, offset: offset)

        setFrame(frame, display: true)
        imageView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        imageView.image = image

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
        imageView.image = nil
    }
}