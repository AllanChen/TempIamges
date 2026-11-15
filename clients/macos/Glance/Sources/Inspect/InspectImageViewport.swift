import AppKit

/// Vision coordinates use a bottom-left origin and are independent of the
/// viewport's current zoom, pan, quarter-turn, or mirror transform.
struct InspectOCRGlyph {
    let character: String
    let boundingBox: CGRect
    let line: Int
}

struct InspectOCRResult {
    let text: String
    let lineBounds: [CGRect]
    let glyphs: [InspectOCRGlyph]
}

/// Rebuilds reading order and line structure from Vision's line observations,
/// which arrive in no guaranteed order and know nothing about rows, columns,
/// or paragraphs. Uses a recursive XY-cut: split into horizontal bands at
/// empty rows, split bands into columns at wide empty gutters, and keep
/// fragments that share a visual row on one output line.
enum InspectOCRLayout {
    struct Fragment {
        let text: String
        /// Pixel space, top-left origin, so x and y distances are comparable.
        let rect: CGRect
    }

    private struct Item {
        let index: Int
        let text: String
        let rect: CGRect
    }

    private struct Line {
        var items: [Item]
        var paragraphBefore = false
    }

    /// Converts a Vision normalized (bottom-left origin) box to `Fragment` space.
    static func fragmentRect(for box: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(x: box.minX * imageSize.width, y: (1 - box.maxY) * imageSize.height,
               width: box.width * imageSize.width, height: box.height * imageSize.height)
    }

    /// Returns fragment indices in reading order and the laid-out text.
    static func layout(_ fragments: [Fragment]) -> (order: [Int], text: String) {
        let items = fragments.enumerated().compactMap { index, fragment -> Item? in
            let text = fragment.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, fragment.rect.height > 0 else { return nil }
            return Item(index: index, text: text, rect: fragment.rect)
        }
        let lines = cut(items)
        var text = ""
        for (offset, line) in lines.enumerated() {
            if offset > 0 { text += line.paragraphBefore ? "\n\n" : "\n" }
            text += join(line.items)
        }
        return (lines.flatMap { $0.items.map(\.index) }, text)
    }

    private static func cut(_ items: [Item]) -> [Line] {
        guard !items.isEmpty else { return [] }
        guard items.count > 1 else { return [Line(items: items)] }

        let bands = split(items, vertical: true, minGap: 0)
        if bands.count > 1 {
            var lines: [Line] = []
            var previous: [Item]?
            for band in bands {
                var sub = cut(band)
                if let previous, !sub.isEmpty {
                    let gap = band.map(\.rect.minY).min()! - previous.map(\.rect.maxY).max()!
                    let lineHeight = min(medianHeight(previous), medianHeight(band))
                    if gap > lineHeight * 0.8 { sub[0].paragraphBefore = true }
                }
                lines += sub
                previous = band
            }
            return lines
        }

        // Fragments that all share some common row stay on one line, even when
        // a wide gap separates them (label / value pairs, table cells).
        let commonTop = items.map(\.rect.minY).max()!
        let commonBottom = items.map(\.rect.maxY).min()!
        if commonTop < commonBottom {
            return [Line(items: items.sorted { $0.rect.minX < $1.rect.minX })]
        }

        let columns = split(items, vertical: false, minGap: medianHeight(items))
        if columns.count > 1 {
            var lines: [Line] = []
            for (offset, column) in columns.enumerated() {
                var sub = cut(column)
                if offset > 0, !sub.isEmpty { sub[0].paragraphBefore = true }
                lines += sub
            }
            return lines
        }
        return rows(items)
    }

    /// Splits items wherever their projection onto one axis leaves an empty
    /// gap wider than `minGap`. Returns a single group when nothing splits.
    private static func split(_ items: [Item], vertical: Bool, minGap: CGFloat) -> [[Item]] {
        let lower: (Item) -> CGFloat = { vertical ? $0.rect.minY : $0.rect.minX }
        let upper: (Item) -> CGFloat = { vertical ? $0.rect.maxY : $0.rect.maxX }
        let sorted = items.sorted { lower($0) < lower($1) }
        var groups: [[Item]] = []
        var current: [Item] = []
        var reach = -CGFloat.greatestFiniteMagnitude
        for item in sorted {
            if !current.isEmpty, lower(item) - reach > minGap {
                groups.append(current)
                current = []
            }
            current.append(item)
            reach = max(reach, upper(item))
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// Fallback for tightly packed text whose boxes overlap between lines:
    /// greedily groups fragments that overlap by at least half a line height.
    private static func rows(_ items: [Item]) -> [Line] {
        var rows: [(rect: CGRect, items: [Item])] = []
        for item in items.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            let match = rows.indices.last { index in
                let row = rows[index].rect
                let overlap = min(row.maxY, item.rect.maxY) - max(row.minY, item.rect.minY)
                return overlap >= min(row.height, item.rect.height) * 0.5
            }
            if let match {
                rows[match].rect = rows[match].rect.union(item.rect)
                rows[match].items.append(item)
            } else {
                rows.append((item.rect, [item]))
            }
        }
        return rows.map { Line(items: $0.items.sorted { $0.rect.minX < $1.rect.minX }) }
    }

    private static func join(_ items: [Item]) -> String {
        var text = ""
        var previous: Item?
        for item in items {
            if let previous {
                let gap = item.rect.minX - previous.rect.maxX
                let height = min(previous.rect.height, item.rect.height)
                if gap > height * 2 {
                    text += "\t"
                } else if !(isCJK(previous.text.last) && isCJK(item.text.first)) {
                    text += " "
                }
            }
            text += item.text
            previous = item
        }
        return text
    }

    private static func medianHeight(_ items: [Item]) -> CGFloat {
        let heights = items.map(\.rect.height).sorted()
        return heights.isEmpty ? 0 : heights[heights.count / 2]
    }

    private static func isCJK(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F, 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
            return true
        default:
            return false
        }
    }
}

private final class InspectTextSelectionView: NSView {
    var rects: [CGRect] = [] { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let fill = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.48)
        fill.setFill()
        for rect in rects where rect.intersects(dirtyRect) {
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }
}

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
            guard image !== oldValue else { return }
            rotationQuarters = 0
            recognizedText = nil
            textSelection = nil
            animationPlayer.setImage(image)
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
    /// The window draws its own load-error view in Focus; compare panes keep this art.
    var showsFailureArt = true {
        didSet { if showsFailureArt != oldValue { updateLoadStatus() } }
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
    private lazy var animationPlayer = ImageAnimationPlayer(view: self, layer: imageLayer)
    private let textSelectionView = InspectTextSelectionView()
    private var recognizedText: InspectOCRResult?
    private var textSelection: ClosedRange<Int>?
    private var textAnchor: Int?
    private var draggingText = false
    /// Slider comparison owns the cursor because its mask is not an NSView clip.
    var managesTextCursor = true
    var onTextCursorGeometryChange: (() -> Void)?
    private var textCursorTrackingArea: NSTrackingArea?
    var textSelectionEnabled = true {
        didSet {
            guard textSelectionEnabled != oldValue else { return }
            if !textSelectionEnabled { clearTextSelection() }
            invalidateTextCursor()
        }
    }
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
        layer?.cornerRadius = 0
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.cornerRadius = 0   // the window clips the corners; nothing may show around the image
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
        addSubview(textSelectionView)
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
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        animationPlayer.refreshVisibility()
    }
    override func viewDidHide() {
        super.viewDidHide()
        animationPlayer.refreshVisibility()
    }
    override func viewDidUnhide() {
        super.viewDidUnhide()
        animationPlayer.refreshVisibility()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
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
        guard isInteractionEnabled else { return nil }
        // The image and selection overlay are visual layers. Keep the viewport
        // itself as the mouse target so a child view cannot absorb text drags.
        return super.hitTest(point) == nil ? nil : self
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
        textSelectionView.frame = bounds
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
        failureView.isHidden = !failed || !showsFailureArt
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
        case .uploading: widgetStatusLabel.stringValue = (task.isPreparing ? "Preparing…" : "Uploading…").localized
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

    func setRecognizedText(_ result: InspectOCRResult?) {
        guard recognizedText?.text != result?.text || recognizedText?.glyphs.count != result?.glyphs.count else { return }
        recognizedText = result
        clearTextSelection()
        invalidateTextCursor()
    }

    var hasSelectedText: Bool { textSelection != nil }

    @discardableResult
    func copySelectedText() -> Bool {
        guard let result = recognizedText, let selection = textSelection,
              result.glyphs.indices.contains(selection.lowerBound),
              result.glyphs.indices.contains(selection.upperBound) else { return false }
        var copied = ""
        var previousLine = result.glyphs[selection.lowerBound].line
        for glyph in result.glyphs[selection] {
            if glyph.line != previousLine {
                copied += "\n"
                previousLine = glyph.line
            }
            copied += glyph.character
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copied, forType: .string)
        return true
    }

    func clearTextSelection() {
        textSelection = nil
        textAnchor = nil
        draggingText = false
        textSelectionView.rects = []
    }

    /// The slider parent owns mouse dispatch, so it forwards text gestures to
    /// whichever image is visible at the pointer before moving its divider.
    func beginTextSelection(at point: CGPoint, clickCount: Int) -> Bool {
        guard textSelectionEnabled, let result = recognizedText,
              let index = glyphIndex(at: point, in: result) else { return false }
        textAnchor = index
        draggingText = true
        if clickCount > 1 {
            let line = result.glyphs[index].line
            let indices = result.glyphs.indices.filter { result.glyphs[$0].line == line }
            if let first = indices.first, let last = indices.last {
                textSelection = first...last
            }
        } else {
            textSelection = index...index
        }
        updateTextSelectionGeometry()
        window?.makeFirstResponder(self)
        return true
    }

    func extendTextSelection(to point: CGPoint) {
        guard draggingText, let result = recognizedText, let anchor = textAnchor,
              let index = nearestGlyphIndex(to: point, in: result) else { return }
        textSelection = min(anchor, index)...max(anchor, index)
        updateTextSelectionGeometry()
    }

    func endTextSelection() { draggingText = false }

    func containsRecognizedText(at point: CGPoint) -> Bool {
        guard textSelectionEnabled, let result = recognizedText else { return false }
        return glyphIndex(at: point, in: result) != nil
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
        let point = convert(event.locationInWindow, from: nil)
        if beginTextSelection(at: point, clickCount: event.clickCount) { return }
        clearTextSelection()
        if event.clickCount == 2 {
            zoom > 1.01 ? fitToView() : setActualSize()
            return
        }
        guard zoom > 1 else { return }
        dragging = true
        lastMouseLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        if draggingText {
            extendTextSelection(to: convert(event.locationInWindow, from: nil))
            return
        }
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

    override func mouseUp(with event: NSEvent) {
        dragging = false
        endTextSelection()
    }

    var recognizedTextCursorRects: [CGRect] {
        guard textSelectionEnabled, image != nil, let result = recognizedText,
              !result.glyphs.isEmpty else { return [] }
        return result.lineBounds.map { textHitRect(for: $0).intersection(visibleRect) }
            .filter { !$0.isNull && !$0.isEmpty }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard managesTextCursor, isInteractionEnabled else { return }
        addCursorRect(visibleRect, cursor: .arrow)
        for rect in recognizedTextCursorRects { addCursorRect(rect, cursor: .iBeam) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let textCursorTrackingArea { removeTrackingArea(textCursorTrackingArea) }
        textCursorTrackingArea = nil
        guard managesTextCursor, isInteractionEnabled else { return }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .cursorUpdate, .mouseMoved], owner: self, userInfo: nil)
        addTrackingArea(area)
        textCursorTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { updateTextCursor(at: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { updateTextCursor(at: event.locationInWindow) }

    private func updateTextCursor(at location: NSPoint) {
        guard managesTextCursor, isInteractionEnabled, !isHiddenOrHasHiddenAncestor,
              let content = window?.contentView else { return }
        let hitPoint = content.superview?.convert(location, from: nil) ?? location
        guard content.hitTest(hitPoint) === self else { return }
        (draggingText || containsRecognizedText(at: convert(location, from: nil)) ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    private func invalidateTextCursor() {
        window?.invalidateCursorRects(for: self)
        onTextCursorGeometryChange?()
        if let window, window.isKeyWindow { updateTextCursor(at: window.mouseLocationOutsideOfEventStream) }
    }

    private func updateLayerGeometry() {
        guard let image, bounds.width > 0, bounds.height > 0 else {
            imageLayer.frame = bounds
            textSelectionView.rects = []
            invalidateTextCursor()
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
        updateTextSelectionGeometry()
        invalidateTextCursor()
    }

    private func viewPoint(for normalized: CGPoint) -> CGPoint {
        guard let image else { return .zero }
        let size = contentSize(for: image)
        let x = (normalized.x - 0.5) * size.width * flipX
        let y = (normalized.y - 0.5) * size.height * flipY
        let angle = -CGFloat(rotationQuarters) * .pi / 2
        let c = cos(angle), s = sin(angle)
        return CGPoint(x: mediaRect.midX + panOffset.x + c * x - s * y,
                       y: mediaRect.midY + panOffset.y + s * x + c * y)
    }

    private func viewRect(for normalized: CGRect) -> CGRect {
        let corners = [CGPoint(x: normalized.minX, y: normalized.minY),
                       CGPoint(x: normalized.maxX, y: normalized.minY),
                       CGPoint(x: normalized.minX, y: normalized.maxY),
                       CGPoint(x: normalized.maxX, y: normalized.maxY)].map(viewPoint(for:))
        guard let first = corners.first else { return .zero }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min() ?? first.x, y: ys.min() ?? first.y,
                      width: max(2, (xs.max() ?? first.x) - (xs.min() ?? first.x)),
                      height: max(2, (ys.max() ?? first.y) - (ys.min() ?? first.y)))
    }

    private func textHitRect(for line: CGRect) -> CGRect {
        viewRect(for: line).insetBy(dx: -4, dy: -4).intersection(bounds)
    }

    private func glyphIndex(at point: CGPoint, in result: InspectOCRResult) -> Int? {
        guard result.lineBounds.contains(where: { textHitRect(for: $0).contains(point) }) else {
            return nil
        }
        return nearestGlyphIndex(to: point, in: result)
    }

    private func nearestGlyphIndex(to point: CGPoint, in result: InspectOCRResult) -> Int? {
        guard let image else { return nil }
        let size = contentSize(for: image)
        guard size.width > 0, size.height > 0 else { return nil }
        let angle = -CGFloat(rotationQuarters) * .pi / 2
        let c = cos(angle), s = sin(angle)
        let dx = point.x - mediaRect.midX - panOffset.x
        let dy = point.y - mediaRect.midY - panOffset.y
        let normalized = CGPoint(x: 0.5 + (c * dx + s * dy) / (size.width * flipX),
                                 y: 0.5 + (-s * dx + c * dy) / (size.height * flipY))
        return result.glyphs.indices.min { left, right in
            let a = result.glyphs[left].boundingBox
            let b = result.glyphs[right].boundingBox
            let ax = (a.midX - normalized.x) * size.width
            let ay = (a.midY - normalized.y) * size.height
            let bx = (b.midX - normalized.x) * size.width
            let by = (b.midY - normalized.y) * size.height
            let ad = ax * ax + ay * ay
            let bd = bx * bx + by * by
            return ad < bd
        }
    }

    private func updateTextSelectionGeometry() {
        guard let result = recognizedText, let selection = textSelection else {
            textSelectionView.rects = []
            return
        }
        textSelectionView.rects = result.glyphs[selection].map {
            viewRect(for: $0.boundingBox).intersection(bounds)
        }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
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
