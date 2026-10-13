import AppKit

final class ImageRevealView: NSView {
    let viewport = InspectImageViewport()
    private let overlayViewport = InspectImageViewport()
    private let loadingView = FocusSweepLoadingView(frame: .zero)
    private let failureView = LoadFailedAnimationView(frame: .zero)
    private let maskLayer = CALayer()
    private let divider = NSView()
    private var fraction: CGFloat = 0.5
    var revealFraction: CGFloat { fraction }
    /// The two panes behind the slider: `base` (image A, shown on the right of
    /// the divider) and `overlay` (image B, shown on the left). They share one
    /// viewport state.
    var capturePanes: (base: CapturePane, overlay: CapturePane)? {
        guard let base = viewport.capturePane, let overlay = overlayViewport.capturePane else { return nil }
        return (base, overlay)
    }
    /// Right-click action-menu callback, shared with the plain viewports.
    var onActionMenu: ((NSEvent) -> Void)?
    weak var dropTarget: MediaDropCanvasView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
        wantsLayer = true
        viewport.loadingIndicatorEnabled = false
        overlayViewport.loadingIndicatorEnabled = false
        addSubview(viewport)
        addSubview(overlayViewport)
        addSubview(loadingView)
        addSubview(failureView)
        failureView.isHidden = true
        overlayViewport.isInteractionEnabled = false
        viewport.onViewportChange = { [weak overlayViewport] state in
            overlayViewport?.apply(state: state, notify: false)
        }
        overlayViewport.wantsLayer = true
        overlayViewport.layer?.mask = maskLayer
        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.textPrimary.withAlphaComponent(0.82).cgColor
        addSubview(divider)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender) == true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    /// A mousedown on the slider drags the reveal divider, never the window.
    /// Without this, `isMovableByWindowBackground` steals the drag and the
    /// whole window moves instead of the comparison handle.
    override var mouseDownCanMoveWindow: Bool { false }

    /// Slider rotates both layers together (the pair shares one viewport state).
    func rotate(byQuarters delta: Int) {
        viewport.rotate(byQuarters: delta)
        overlayViewport.rotate(byQuarters: delta)
    }

    func flip(horizontal: Bool) {
        viewport.flip(horizontal: horizontal)
        overlayViewport.flip(horizontal: horizontal)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let onActionMenu {
            onActionMenu(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    func setImages(a: NSImage?, b: NSImage?, failed: Bool = false) {
        viewport.image = a
        overlayViewport.image = b
        let isWaitingForPair = a == nil || b == nil
        viewport.isHidden = isWaitingForPair
        overlayViewport.isHidden = isWaitingForPair
        divider.isHidden = isWaitingForPair
        failureView.isHidden = !failed
        loadingView.setLoading(isWaitingForPair && !failed)
    }

    override func layout() {
        super.layout()
        viewport.frame = bounds
        overlayViewport.frame = bounds
        let loaderSize = FocusSweepLoadingView.preferredSize
        loadingView.frame = NSRect(x: bounds.midX - loaderSize.width / 2,
                                   y: bounds.midY - loaderSize.height / 2,
                                   width: loaderSize.width,
                                   height: loaderSize.height)
        let failureSize = LoadFailedAnimationView.preferredSize
        failureView.frame = NSRect(x: bounds.midX - failureSize.width / 2,
                                   y: bounds.midY - failureSize.height / 2,
                                   width: failureSize.width,
                                   height: failureSize.height)
        updateMask()
    }

    override func mouseDragged(with event: NSEvent) {
        fraction = max(0, min(1, convert(event.locationInWindow, from: nil).x / max(bounds.width, 1)))
        updateMask()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            viewport.mouseDown(with: event)
            overlayViewport.apply(state: viewport.viewportState, notify: false)
            return
        }
        fraction = max(0, min(1, convert(event.locationInWindow, from: nil).x / max(bounds.width, 1)))
        updateMask()
    }

    override func scrollWheel(with event: NSEvent) {
        // While zoomed in, every scroll pans/zooms the pair as usual. At fit
        // scale, a horizontal two/three-finger swipe nudges the reveal divider.
        let zoomedIn = viewport.viewportState.zoomRelativeToFit > 1.01
        if zoomedIn || event.subtype == .mouseEvent
            || abs(event.scrollingDeltaX) <= abs(event.scrollingDeltaY) {
            viewport.scrollWheel(with: event)
            overlayViewport.apply(state: viewport.viewportState, notify: false)
            return
        }
        let step = event.scrollingDeltaX / max(bounds.width, 1)
        fraction = max(0, min(1, fraction + step))
        updateMask()
    }

    /// Three-finger swipe (System Settings → Trackpad → "Swipe between pages").
    override func swipe(with event: NSEvent) {
        guard event.deltaX != 0 else { return }
        fraction = max(0, min(1, fraction - event.deltaX * 0.1))
        updateMask()
    }

    override func magnify(with event: NSEvent) {
        viewport.magnify(with: event)
        overlayViewport.apply(state: viewport.viewportState, notify: false)
    }

    private func updateMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.backgroundColor = NSColor.black.cgColor
        maskLayer.frame = NSRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        divider.frame = NSRect(x: bounds.width * fraction - 1, y: 0, width: 2, height: bounds.height)
        CATransaction.commit()
    }
}
