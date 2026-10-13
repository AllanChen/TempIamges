import AppKit

struct InspectViewportState {
    var zoomRelativeToFit: CGFloat
    var normalizedCenter: CGPoint
}

final class InspectImageViewport: NSView {
    private var flipX: CGFloat = 1
    private var flipY: CGFloat = 1
    var image: NSImage? {
        didSet {
            // Only reset rotation when a DIFFERENT image is assigned — session
            // re-renders re-assign the same instance after async metadata loads.
            if image !== oldValue { rotationQuarters = 0 }
            imageLayer.contents = image
            updateLoadStatus()
            fitToView()
        }
    }
    var onViewportChange: ((InspectViewportState) -> Void)?
    var isInteractionEnabled = true
    /// Right-click action-menu callback (rotate, export, OCR…). Wired by the
    /// window to present the themed ActionMenuPanel.
    var onActionMenu: ((NSEvent) -> Void)?
    weak var dropTarget: MediaDropCanvasView?
    /// Quarter-turns clockwise applied to the VIEW only (0–3). The file on
    /// disk is never modified; resets when a different image is assigned.
    private(set) var rotationQuarters = 0
    var loadingIndicatorEnabled = true {
        didSet { updateLoadStatus() }
    }
    /// Marks which compare slot is active — the side a filmstrip tap replaces.
    var isActiveSlot = false {
        didSet {
            updateActiveIndicator()
        }
    }
    var viewportState: InspectViewportState {
        InspectViewportState(zoomRelativeToFit: zoom, normalizedCenter: normalizedCenter)
    }

    /// Everything needed to re-render what this viewport shows at the image's
    /// full resolution (view-only rotation and flips included).
    var capturePane: CapturePane? {
        guard let image, mediaRect.width > 0, mediaRect.height > 0 else { return nil }
        return CapturePane(image: image, quarters: rotationQuarters,
                           flipX: flipX < 0, flipY: flipY < 0,
                           paneSize: mediaRect.size, zoom: zoom, center: normalizedCenter)
    }

    /// Where the visible part of the image sits on screen, in `target`'s
    /// top-left coordinates. The capture editor draws its frozen picture here
    /// so it opens exactly over the original.
    func captureDisplayRect(in target: NSView) -> CGRect? {
        guard let pane = capturePane,
              let cg = pane.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let odd = abs(pane.quarters) % 2 == 1
        let pixels = CGSize(width: odd ? cg.height : cg.width, height: odd ? cg.width : cg.height)
        let d = CaptureGeometry.displayedRect(imagePixels: pixels, paneSize: pane.paneSize, zoom: pane.zoom)
        let local = CGRect(x: mediaRect.minX + d.minX, y: mediaRect.minY + (mediaRect.height - d.maxY),
                           width: d.width, height: d.height)
        let r = convert(local, to: target)
        return target.isFlipped ? r : CGRect(x: r.minX, y: target.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    private let imageLayer = CALayer()
    private let activeIndicator = CALayer()
    private let loadingView = FocusSweepLoadingView(frame: .zero)
    private let failureView = LoadFailedAnimationView(frame: .zero)
    private let widgetOverlay = NSVisualEffectView()
    private let widgetLoadingView = FocusSweepLoadingView(frame: .zero)
    private let widgetStatusLabel = NSTextField(labelWithString: "")
    private var loadFailed = false
    private var zoom: CGFloat = 1
    /// V3 Simple Operation has no inner canvas/card margin: the media is the
    /// window's content plane and chrome merely floats over it.
    private let canvasInset: CGFloat = 0
    private var normalizedCenter = CGPoint(x: 0.5, y: 0.5)
    private var panOffset = CGPoint.zero
    private var lastMouseLocation = CGPoint.zero
    private var dragging = false
    private var compareDimmed = false

    /// The media viewport is flush to every edge of the operation canvas.
    private var mediaRect: NSRect {
        NSRect(x: canvasInset,
               y: 0,
               width: max(0, bounds.width - canvasInset * 2),
               height: bounds.height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.cornerRadius = 5
        imageLayer.masksToBounds = true
        imageLayer.borderWidth = 0
        layer?.addSublayer(imageLayer)
        // Compare selection is communicated by gently dimming the inactive
        // side. Keep the selected side completely free of a border/glow.
        activeIndicator.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
        activeIndicator.borderWidth = 0
        activeIndicator.cornerRadius = 0
        activeIndicator.shadowOpacity = 0
        activeIndicator.opacity = 0
        layer?.addSublayer(activeIndicator)
        addSubview(loadingView)
        addSubview(failureView)
        failureView.isHidden = true
        widgetOverlay.material = .underWindowBackground
        widgetOverlay.blendingMode = .withinWindow
        widgetOverlay.state = .active
        widgetOverlay.wantsLayer = true
        widgetOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        widgetOverlay.isHidden = true
        widgetStatusLabel.textColor = PanelStyle.textPrimary
        widgetStatusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        widgetStatusLabel.alignment = .center
        widgetOverlay.addSubview(widgetLoadingView)
        widgetOverlay.addSubview(widgetStatusLabel)
        addSubview(widgetOverlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
        if !widgetOverlay.isHidden { return widgetOverlay.hitTest(point) ?? widgetOverlay }
        return isInteractionEnabled ? super.hitTest(point) : nil
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
        let indicatorRect = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activeIndicator.frame = indicatorRect
        CATransaction.commit()
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
        widgetOverlay.frame = bounds
        let widgetLoaderSize = FocusSweepLoadingView.preferredSize
        widgetLoadingView.frame = NSRect(x: bounds.midX - widgetLoaderSize.width / 2,
                                         y: bounds.midY - widgetLoaderSize.height / 2 + 14,
                                         width: widgetLoaderSize.width, height: widgetLoaderSize.height)
        widgetStatusLabel.frame = NSRect(x: 20, y: bounds.midY - 42, width: bounds.width - 40, height: 22)
    }

    func setLoadFailed(_ failed: Bool) {
        loadFailed = failed
        updateLoadStatus()
    }

    private func updateLoadStatus() {
        let failed = image == nil && loadFailed
        failureView.isHidden = !failed
        loadingView.setLoading(image == nil && loadingIndicatorEnabled && !failed)
    }

    func setActiveIndicatorVisible(_ visible: Bool, animated _: Bool, duration _: CFTimeInterval) {
        // Kept for callers that control toolbar visibility. Compare dimming
        // itself is persistent and is managed by setCompareDimmed(_:).
    }

    func setCompareDimmed(_ dimmed: Bool) {
        compareDimmed = dimmed
        updateActiveIndicator()
    }

    func setWidgetProcessing(_ task: WidgetTaskRecord?) {
        // The window draws the non-blocking main-image cue. Keep this legacy
        // full-canvas overlay hidden so the image stays available for inspection.
        widgetOverlay.isHidden = true
        widgetLoadingView.setLoading(false)
        isInteractionEnabled = true
        guard let task else { widgetStatusLabel.stringValue = ""; return }
        switch task.phase {
        case .uploading: widgetStatusLabel.stringValue = "Uploading…".localized
        case .submitting: widgetStatusLabel.stringValue = "Submitting…".localized
        case .processing: widgetStatusLabel.stringValue = task.progress > 0 ? "Processing \(task.progress)%" : "Processing…".localized
        case .downloading: widgetStatusLabel.stringValue = "Downloading result…".localized
        default: widgetStatusLabel.stringValue = "Processing…".localized
        }
        setAccessibilityElement(true)
        setAccessibilityLabel(widgetStatusLabel.stringValue)
    }

    private func updateActiveIndicator() {
        let isVisible = compareDimmed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activeIndicator.opacity = isVisible ? 1 : 0
        CATransaction.commit()
    }

    func fitToView() {
        zoom = 1
        panOffset = .zero
        normalizedCenter = CGPoint(x: 0.5, y: 0.5)
        updateLayerGeometry()
        notify()
    }

    /// Toolbar ± buttons: multiply the current zoom, clamped to 1–20.
    func zoomBy(_ factor: CGFloat) {
        guard image != nil else { return }
        zoom = max(1, min(20, zoom * factor))
        updateLayerGeometry()
        notify()
    }

    /// On-screen scale as a percentage (fit = image's natural fit scale).
    var zoomPercent: Int {
        guard let image else { return 100 }
        return Int((fitScale(for: image) * zoom * 100).rounded())
    }

    func setActualSize() {
        guard let image, bounds.width > 0, bounds.height > 0 else { return }
        let fit = fitScale(for: image)
        zoom = max(1, min(20, 1 / max(fit, 0.0001)))
        panOffset = .zero
        normalizedCenter = CGPoint(x: 0.5, y: 0.5)
        updateLayerGeometry()
        notify()
    }

    func apply(state: InspectViewportState, notify shouldNotify: Bool) {
        guard let image else { return }
        zoom = max(1, min(20, state.zoomRelativeToFit))
        normalizedCenter = state.normalizedCenter
        let rendered = renderedSize(for: image)
        panOffset = CGPoint(x: (0.5 - normalizedCenter.x) * rendered.width,
                            y: (0.5 - normalizedCenter.y) * rendered.height)
        constrainPan(rendered: rendered)
        updateLayerGeometry()
        if shouldNotify { notify() }
    }

    /// Rotate the view layer by 90° steps (view-only; the file is untouched).
    func rotate(byQuarters delta: Int) {
        guard image != nil else { return }
        rotationQuarters = ((rotationQuarters + delta) % 4 + 4) % 4
        updateLayerGeometry()
        notify()
    }

    func flip(horizontal: Bool) {
        if horizontal { flipX *= -1 } else { flipY *= -1 }
        updateLayerGeometry()
        notify()
    }

    override func rightMouseDown(with event: NSEvent) {
        if let onActionMenu {
            onActionMenu(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let image else { return }
        // Once zoomed, trackpad two-finger scrolling is panning (matching the
        // Preview image viewer), not another zoom gesture.
        if zoom > 1.0 {
            panOffset.x -= event.scrollingDeltaX
            panOffset.y -= event.scrollingDeltaY
            constrainPan(rendered: renderedSize(for: image))
        } else if event.modifierFlags.contains(.command) || abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            let point = convert(event.locationInWindow, from: nil)
            let before = imagePoint(at: point, image: image)
            let factor = pow(1.08, event.scrollingDeltaY)
            zoom = max(1, min(20, zoom * factor))
            setCenter(so: before, remainsAt: point, image: image)
        }
        updateLayerGeometry()
        notify()
    }

    override func magnify(with event: NSEvent) {
        window?.makeFirstResponder(self)
        zoom = max(1, min(20, zoom * (1 + event.magnification)))
        updateLayerGeometry()
        notify()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            zoom > 1.01 ? fitToView() : setActualSize()
            return
        }
        guard zoom > 1 else { return }
        dragging = true
        lastMouseLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let location = event.locationInWindow
        let delta = CGPoint(x: location.x - lastMouseLocation.x,
                            y: location.y - lastMouseLocation.y)
        panOffset.x += delta.x
        panOffset.y += delta.y
        lastMouseLocation = location
        let rendered = renderedSize(for: image!)
        constrainPan(rendered: rendered)
        normalizedCenter = CGPoint(x: 0.5 - panOffset.x / max(rendered.width, 1),
                                   y: 0.5 - panOffset.y / max(rendered.height, 1))
        updateLayerGeometry()
        notify()
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    private func updateLayerGeometry() {
        guard let image, bounds.width > 0, bounds.height > 0 else {
            imageLayer.frame = bounds
            return
        }
        let rendered = renderedSize(for: image)
        constrainPan(rendered: rendered)
        let centerX = mediaRect.midX + panOffset.x
        let centerY = mediaRect.midY + panOffset.y
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The layer keeps the UNROTATED rendered size so resizeAspect fills it
        // exactly; quarter-turns are applied via the layer transform, and the
        // view-space width/height swap happens in renderedSize(for:).
        imageLayer.bounds = NSRect(origin: .zero, size: contentSize(for: image))
        imageLayer.position = CGPoint(x: centerX, y: centerY)
        var transform = CATransform3DMakeRotation(-CGFloat(rotationQuarters) * .pi / 2, 0, 0, 1)
        transform = CATransform3DScale(transform, flipX, flipY, 1)
        imageLayer.transform = transform
        CATransaction.commit()
    }

    /// Fit scale against the (possibly width/height-swapped) rotated size.
    private func fitScale(for image: NSImage) -> CGFloat {
        let size = rotationQuarters % 2 == 1
            ? CGSize(width: image.size.height, height: image.size.width)
            : image.size
        let canvas = mediaRect
        return min(canvas.width / size.width, canvas.height / size.height)
    }

    /// Layer bounds — the rendered size BEFORE rotation.
    private func contentSize(for image: NSImage) -> CGSize {
        let scale = fitScale(for: image) * zoom
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    /// View-space size — what the rotated image occupies on screen.
    private func renderedSize(for image: NSImage) -> CGSize {
        let content = contentSize(for: image)
        return rotationQuarters % 2 == 1
            ? CGSize(width: content.height, height: content.width)
            : content
    }

    private func imagePoint(at viewPoint: CGPoint, image: NSImage) -> CGPoint {
        let rendered = renderedSize(for: image)
        let centerX = mediaRect.midX + (0.5 - normalizedCenter.x) * rendered.width
        let centerY = mediaRect.midY + (0.5 - normalizedCenter.y) * rendered.height
        return CGPoint(x: (viewPoint.x - centerX) / rendered.width + 0.5,
                       y: (viewPoint.y - centerY) / rendered.height + 0.5)
    }

    private func setCenter(so imagePoint: CGPoint, remainsAt viewPoint: CGPoint, image: NSImage) {
        let rendered = renderedSize(for: image)
        normalizedCenter.x = 0.5 - (viewPoint.x - mediaRect.midX - (imagePoint.x - 0.5) * rendered.width) / rendered.width
        normalizedCenter.y = 0.5 - (viewPoint.y - mediaRect.midY - (imagePoint.y - 0.5) * rendered.height) / rendered.height
        panOffset = CGPoint(x: (0.5 - normalizedCenter.x) * rendered.width,
                            y: (0.5 - normalizedCenter.y) * rendered.height)
        constrainPan(rendered: rendered)
    }

    private func constrainPan(rendered: CGSize) {
        let maxPanX = max(0, (rendered.width - mediaRect.width) / 2)
        let maxPanY = max(0, (rendered.height - mediaRect.height) / 2)
        panOffset.x = max(-maxPanX, min(maxPanX, panOffset.x))
        panOffset.y = max(-maxPanY, min(maxPanY, panOffset.y))
        normalizedCenter = CGPoint(x: 0.5 - panOffset.x / max(rendered.width, 1),
                                   y: 0.5 - panOffset.y / max(rendered.height, 1))
    }

    private func notify() {
        onViewportChange?(InspectViewportState(zoomRelativeToFit: zoom, normalizedCenter: normalizedCenter))
    }
}
