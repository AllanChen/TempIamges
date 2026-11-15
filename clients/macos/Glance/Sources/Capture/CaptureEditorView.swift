import AppKit

/// Full-window capture overlay (Figma Shizuka `24 · Capture`): the frozen
/// picture, a dim outside the crop frame, the white frame with thirds and 8
/// handles, the pixel size tag above it, the floating capture toolbar
/// (Ratio segment | close | Save) below it and the shortcut hint pill.
///
/// Everything is laid out in flipped (top-left) coordinates so the numbers can
/// be read straight off the Figma frame.
final class CaptureEditorView: NSView {
    var onCancel: (() -> Void)?
    var onCapture: ((CGImage) -> Void)?

    private let frozen: CGImage
    private let nsImage: NSImage
    private var ratio: CaptureRatio = .free

    /// Selection as a unit rect over the displayed image, so it survives resizes.
    /// Starts as a centred square (the Free ratio, with a 1:1 starting shape).
    private var unitSelection = CGRect(x: 0, y: 0, width: 1, height: 1)

    private let bar = CaptureBar()
    private let hint = CaptureHintPill()

    private enum Drag {
        case none
        case handle(CaptureHandle, start: CGRect)
        case move(start: CGRect, origin: CGPoint)
        case fresh(origin: CGPoint)
    }
    private var drag: Drag = .none

    // Figma metrics (24 · Capture, 1440 × 900 board).
    private let handleSize: CGFloat = 7
    /// The toolbar sits 14 pt below the frame, right-aligned with it.
    private let barGap: CGFloat = 14
    /// The hint pill's foot is 31 pt above the bottom edge.
    private let hintBottomInset: CGFloat = 31
    /// Where the frozen picture sits, in this view's top-left coordinates —
    /// the spot it occupied on screen, so opening the editor doesn't move it.
    /// Nil fits the picture to the whole view.
    private let displayRect: CGRect?

    override var isFlipped: Bool { true }
    // The host window drags by its background; the editor must keep those drags.
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    init(image: CGImage, displayRect: CGRect? = nil) {
        frozen = image
        self.displayRect = displayRect
        nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        super.init(frame: .zero)
        // 70% of the short side, so the box has room to grow.
        let shortSide = CGFloat(min(image.width, image.height)) * 0.7
        let w = shortSide / CGFloat(image.width), h = shortSide / CGFloat(image.height)
        unitSelection = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
        wantsLayer = true
        autoresizingMask = [.width, .height]

        bar.selected = ratio
        bar.onSelect = { [weak self] picked in self?.pick(picked) }
        bar.onCancel = { [weak self] in self?.onCancel?() }
        bar.onCapture = { [weak self] in self?.commit() }
        addSubview(bar)
        addSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Geometry

    private var imageRect: CGRect {
        let area = displayRect ?? bounds
        return CaptureGeometry.aspectFit(CGSize(width: frozen.width, height: frozen.height), in: area)
    }

    private var selection: CGRect {
        get {
            let r = imageRect
            return CGRect(x: r.minX + unitSelection.minX * r.width, y: r.minY + unitSelection.minY * r.height,
                          width: unitSelection.width * r.width, height: unitSelection.height * r.height)
        }
        set {
            let r = imageRect
            guard r.width > 0, r.height > 0 else { return }
            unitSelection = CGRect(x: (newValue.minX - r.minX) / r.width, y: (newValue.minY - r.minY) / r.height,
                                   width: newValue.width / r.width, height: newValue.height / r.height)
            needsDisplay = true
            needsLayout = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private var pixelCrop: CGRect {
        CaptureGeometry.cropRect(selection: selection, imageRect: imageRect,
                                 imagePixels: CGSize(width: frozen.width, height: frozen.height))
    }

    override func layout() {
        super.layout()
        let hintSize = hint.preferredSize
        hint.frame = CGRect(x: ((bounds.width - hintSize.width) / 2).rounded(),
                            y: bounds.height - hintBottomInset - hintSize.height,
                            width: hintSize.width, height: hintSize.height)
        // Below the frame and right-aligned with it; above it when there is no
        // room below, and inside its foot when there is room on neither side.
        let size = bar.preferredSize
        let box = selection
        let floor = hint.frame.minY - 8
        var y = box.maxY + barGap
        if y + size.height > floor {
            y = box.minY - barGap - size.height
            if y < 8 { y = min(box.maxY, floor) - barGap - size.height }
        }
        let x = min(max(8, box.maxX - size.width), bounds.width - size.width - 8)
        bar.frame = CGRect(x: x.rounded(), y: max(8, y).rounded(), width: size.width, height: size.height)
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Actions

    private func pick(_ picked: CaptureRatio) {
        ratio = picked
        bar.selected = picked
        // Centred in the picture at 70% of its extent, so there is room to
        // move and enlarge the box instead of it filling the whole image.
        let image = imageRect
        let room = image.insetBy(dx: image.width * 0.15, dy: image.height * 0.15)
        if let fitted = CaptureGeometry.fit(picked, around: CGPoint(x: image.midX, y: image.midY), in: room) {
            selection = fitted
        }
    }

    private func commit() {
        guard let cropped = frozen.cropping(to: pixelCrop) else { return }
        onCapture?(cropped)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        PanelStyle.inspectBackground.setFill()
        bounds.fill()

        let image = imageRect
        nsImage.draw(in: image, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])

        // Marks over the picture are literal black and white, as in Figma.
        let box = selection
        let mask = NSBezierPath(rect: bounds)
        mask.append(NSBezierPath(rect: box))
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.55).setFill()
        mask.fill()

        // Thirds, 1 pt.
        NSColor.white.withAlphaComponent(0.28).setFill()
        for i in 1...2 {
            let x = (box.minX + box.width * CGFloat(i) / 3).rounded(.down)
            let y = (box.minY + box.height * CGFloat(i) / 3).rounded(.down)
            CGRect(x: x, y: box.minY, width: 1, height: box.height).fill()
            CGRect(x: box.minX, y: y, width: box.width, height: 1).fill()
        }

        // Selection, 1 pt white inside the frame.
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        outline.stroke()

        drawHandles(on: box)
        drawSizeTag(for: box)
    }

    /// Figma `handle`: 7 pt white squares centred on the frame's corners and edges.
    private func drawHandles(on box: CGRect) {
        NSColor.white.setFill()
        for handle in CaptureHandle.allCases {
            let p = handle.position(on: box)
            CGRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2, width: handleSize, height: handleSize).fill()
        }
    }

    /// Figma size tag: ink/0, radius 3, mono 11 text/1 with 8 × 3 padding,
    /// its foot 6 pt above the frame.
    private func drawSizeTag(for box: CGRect) {
        let crop = pixelCrop
        let text = "\(Int(crop.width)) × \(Int(crop.height))"
        let font = PanelStyle.monoFont(ofSize: 11)
        let width = InspectText.width(text, font: font) + 16
        let frame = CGRect(x: box.minX, y: max(8, box.minY - 26), width: width, height: 20)
        InspectInk.ink0.setFill()
        NSBezierPath(roundedRect: frame, xRadius: PanelStyle.Radius.thumb, yRadius: PanelStyle.Radius.thumb).fill()
        InspectText.draw(text, in: CGRect(x: frame.minX + 8, y: frame.minY + 3, width: width - 16, height: 14),
                         font: font, color: InspectInk.text1, truncation: .byClipping)
    }

    // MARK: Mouse

    override func resetCursorRects() {
        let box = selection
        addCursorRect(box, cursor: .openHand)
        for handle in CaptureHandle.allCases {
            let p = handle.position(on: box)
            let rect = CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)
            let cursor: NSCursor
            if handle.isCorner { cursor = .crosshair }
            else if handle.movesLeft || handle.movesRight { cursor = .resizeLeftRight }
            else { cursor = .resizeUpDown }
            addCursorRect(rect, cursor: cursor)
        }
    }

    private func handle(at point: CGPoint) -> CaptureHandle? {
        let box = selection
        return CaptureHandle.allCases.first { handle in
            let p = handle.position(on: box)
            return abs(p.x - point.x) <= 9 && abs(p.y - point.y) <= 9
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let area = imageRect
        if let handle = handle(at: point) {
            drag = .handle(handle, start: selection)
        } else if selection.contains(point) {
            drag = .move(start: selection, origin: point)
        } else if area.contains(point) {
            drag = .fresh(origin: point)
        } else {
            drag = .none
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let area = imageRect
        switch drag {
        case .none:
            break
        case .handle(let handle, let start):
            selection = CaptureGeometry.resize(start, handle: handle, to: point, aspect: ratio.aspect, in: area)
        case .move(let start, let origin):
            selection = CaptureGeometry.move(start, by: CGPoint(x: point.x - origin.x, y: point.y - origin.y), in: area)
        case .fresh(let origin):
            // Pick the corner that points from the press toward the cursor.
            let right = point.x >= origin.x, down = point.y >= origin.y
            let handle: CaptureHandle = right ? (down ? .bottomRight : .topRight) : (down ? .bottomLeft : .topLeft)
            let start = CGRect(origin: origin, size: .zero)
            selection = CaptureGeometry.resize(start, handle: handle, to: point, aspect: ratio.aspect, in: area)
        }
    }

    override func mouseUp(with event: NSEvent) {
        drag = .none
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // esc
            onCancel?()
        case 36, 76: // return, enter
            commit()
        default:
            super.keyDown(with: event)
        }
    }
}

private extension CaptureRatio {
    var displayLabel: String { self == .free ? "Free".localized : label }
    /// Figma's segment order: Free, square, landscape before portrait.
    static let segmentOrder: [CaptureRatio] = [.free, .square, .fourThree, .threeFour, .sixteenNine, .nineSixteen]
}

// MARK: - Toolbar

/// Figma `capture toolbar`: ink/1, a line rule, radius 8, 46 pt high —
/// "Ratio", the ratio segments, a divider, close, and the primary Save.
private final class CaptureBar: NSView {
    var selected: CaptureRatio = .free { didSet { segments.selected = selected } }
    var onSelect: ((CaptureRatio) -> Void)? {
        get { segments.onSelect }
        set { segments.onSelect = newValue }
    }
    var onCancel: (() -> Void)?
    var onCapture: (() -> Void)?

    private let ratioLabel = InspectTextLabel("Ratio".localized, font: PanelStyle.inspectFont(ofSize: 12),
                                              color: InspectInk.text3)
    private let segments = CaptureRatioSegments()
    private let divider = NSView()
    private let close = InspectToolbarButton(symbol: "xmark", tooltip: "Cancel".localized)
    private lazy var save = InspectDialogButton.make("Save".localized, primary: true,
                                                     target: self, action: #selector(saveTapped))

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.cornerSmall
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(InspectInk.line)
        layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.ink1)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Capture".localized)
        addSubview(ratioLabel)
        addSubview(segments)
        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
        addSubview(divider)
        close.usesShizukaStyle = true
        close.target = self
        close.action = #selector(cancelTapped)
        close.updateTooltip("Cancel".localized)
        addSubview(close)
        addSubview(save)
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var saveWidth: CGFloat { InspectDialogButton.width(save.title) }

    /// Label frame 7 + 41, then 4 pt gaps: segments, divider, close (28), Save; 7 pt right padding.
    var preferredSize: CGSize {
        CGSize(width: 7 + 41 + 4 + segments.preferredWidth + 4 + 1 + 4 + 28 + 4 + saveWidth + 7, height: 46)
    }

    override func layout() {
        super.layout()
        let labelWidth = max(25, ratioLabel.preferredWidth)
        ratioLabel.frame = CGRect(x: 15, y: 15.5, width: labelWidth, height: 15)
        segments.frame = CGRect(x: 52, y: 10.5, width: segments.preferredWidth, height: 25)
        divider.frame = CGRect(x: segments.frame.maxX + 4, y: 14, width: 1, height: 18)
        close.frame = CGRect(x: divider.frame.maxX + 4, y: 9, width: 28, height: 28)
        save.frame = CGRect(x: close.frame.maxX + 4, y: 7, width: saveWidth, height: 32)
    }

    @objc private func cancelTapped() { onCancel?() }
    @objc private func saveTapped() { onCapture?() }
}

/// Figma ratio segments: 25 pt high, 10 pt side padding, 4 pt apart, 12 pt
/// text/2; the selected ratio on ink/4 in text/1.
private final class CaptureRatioSegments: NSView {
    var selected: CaptureRatio = .free { didSet { needsDisplay = true; updateAccessibility() } }
    var onSelect: ((CaptureRatio) -> Void)?
    private var hovered: CaptureRatio?
    private static let font = PanelStyle.inspectFont(ofSize: 12)
    private static let selectedFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Ratio".localized)
        updateAccessibility()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var frames: [(CaptureRatio, CGRect)] {
        var x: CGFloat = 0
        return CaptureRatio.segmentOrder.map { ratio in
            let width = InspectText.width(ratio.displayLabel, font: Self.selectedFont) + 20
            defer { x += width + 4 }
            return (ratio, CGRect(x: x, y: 0, width: width, height: 25))
        }
    }

    var preferredWidth: CGFloat { frames.last.map { $0.1.maxX } ?? 0 }

    private func ratio(at point: CGPoint) -> CaptureRatio? {
        frames.first { $0.1.contains(point) }?.0
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        hovered = ratio(at: convert(event.locationInWindow, from: nil)); needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        if let picked = ratio(at: convert(event.locationInWindow, from: nil)) { onSelect?(picked) }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (ratio, frame) in frames {
            let isSelected = ratio == selected
            if isSelected || hovered == ratio {
                (isSelected ? InspectInk.ink4 : PanelStyle.controlFill).setFill()
                NSBezierPath(roundedRect: frame, xRadius: PanelStyle.Radius.control,
                             yRadius: PanelStyle.Radius.control).fill()
            }
            InspectText.draw(ratio.displayLabel, in: CGRect(x: frame.minX, y: 5, width: frame.width, height: 15),
                             font: isSelected ? Self.selectedFont : Self.font,
                             color: isSelected || hovered == ratio ? InspectInk.text1 : InspectInk.text2,
                             align: .center, truncation: .byClipping)
        }
    }

    private func updateAccessibility() {
        setAccessibilityValue(selected.displayLabel)
    }
}

// MARK: - Hint

/// Figma hint pill: ink/1, radius 6, 12 pt text/2 with 10 × 5 padding.
private final class CaptureHintPill: NSView {
    private let text = "Drag to select · ↵ save · esc cancel".localized
    private static let font = PanelStyle.inspectFont(ofSize: 12)

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var preferredSize: CGSize { CGSize(width: InspectText.width(text, font: Self.font) + 20, height: 25) }

    override func draw(_ dirtyRect: NSRect) {
        InspectInk.ink1.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: PanelStyle.Radius.control, yRadius: PanelStyle.Radius.control).fill()
        InspectText.draw(text, in: CGRect(x: 10, y: 5, width: bounds.width - 20, height: 15),
                         font: Self.font, color: InspectInk.text2, align: .center, truncation: .byClipping)
    }
}
