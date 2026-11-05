import AppKit

/// Full-window capture overlay (Figma "Capture Editor"): the frozen picture,
/// a 55% mask outside the crop box, the crop box with thirds and 8 handles, a
/// size readout and the floating bar (ratio dropdown | Cancel | Capture).
///
/// Everything is laid out in flipped (top-left) coordinates so the numbers can
/// be read straight off the Figma frame.
final class CaptureEditorView: NSView {
    var onCancel: (() -> Void)?
    var onCapture: ((CGImage) -> Void)?

    private let frozen: CGImage
    private let nsImage: NSImage
    private var ratio: CaptureRatio = .free
    private var listOpen = false

    /// Selection as a unit rect over the displayed image, so it survives resizes.
    /// Starts as a centred square (the Free ratio, with a 1:1 starting shape).
    private var unitSelection = CGRect(x: 0, y: 0, width: 1, height: 1)

    private let bar = CaptureBar()
    private let list = CaptureRatioList()

    private enum Drag {
        case none
        case handle(CaptureHandle, start: CGRect)
        case move(start: CGRect, origin: CGPoint)
        case fresh(origin: CGPoint)
    }
    private var drag: Drag = .none

    // Figma metrics (Capture Editor, 1554 × 1012 board).
    private let handleSize: CGFloat = 10
    private let barBottomInset: CGFloat = 24
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

        bar.ratioText = ratio.displayLabel
        bar.onToggleList = { [weak self] in self?.toggleList() }
        bar.onCancel = { [weak self] in self?.onCancel?() }
        bar.onCapture = { [weak self] in self?.commit() }
        addSubview(bar)

        list.isHidden = true
        list.onSelect = { [weak self] picked in self?.pick(picked) }
        addSubview(list)
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
            window?.invalidateCursorRects(for: self)
        }
    }

    private var pixelCrop: CGRect {
        CaptureGeometry.cropRect(selection: selection, imageRect: imageRect,
                                 imagePixels: CGSize(width: frozen.width, height: frozen.height))
    }

    override func layout() {
        super.layout()
        // Bar: 362 × 52, centred, 24 above the bottom edge.
        let barSize = CaptureBar.size
        bar.frame = CGRect(x: ((bounds.width - barSize.width) / 2).rounded(),
                           y: bounds.height - barBottomInset - barSize.height,
                           width: barSize.width, height: barSize.height)
        // List opens upward, 8 above the bar, aligned with the dropdown.
        let listSize = CaptureRatioList.size
        list.frame = CGRect(x: bar.frame.minX + 8, y: bar.frame.minY - 8 - listSize.height,
                            width: listSize.width, height: listSize.height)
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Actions

    private func toggleList() {
        listOpen.toggle()
        list.selected = ratio
        list.isHidden = !listOpen
    }

    private func closeList() {
        guard listOpen else { return }
        listOpen = false
        list.isHidden = true
    }

    private func pick(_ picked: CaptureRatio) {
        ratio = picked
        bar.ratioText = picked.displayLabel
        closeList()
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

        let box = selection
        let mask = NSBezierPath(rect: bounds)
        mask.append(NSBezierPath(rect: box))
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.55).setFill()
        mask.fill()

        // Thirds.
        NSColor.white.withAlphaComponent(0.28).setStroke()
        let thirds = NSBezierPath()
        thirds.lineWidth = 1
        for i in 1...2 {
            let x = box.minX + box.width * CGFloat(i) / 3
            let y = box.minY + box.height * CGFloat(i) / 3
            thirds.move(to: CGPoint(x: x, y: box.minY)); thirds.line(to: CGPoint(x: x, y: box.maxY))
            thirds.move(to: CGPoint(x: box.minX, y: y)); thirds.line(to: CGPoint(x: box.maxX, y: y))
        }
        thirds.stroke()

        // Crop box, 1.5 pt stroke.
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let outline = NSBezierPath(rect: box)
        outline.lineWidth = 1.5
        outline.stroke()

        drawHandles(on: box)
        drawReadout(for: box)
    }

    private func drawHandles(on box: CGRect) {
        for handle in CaptureHandle.allCases {
            let p = handle.position(on: box)
            let rect = CGRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2, width: handleSize, height: handleSize)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)   // flipped: negative height = down
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawReadout(for box: CGRect) {
        let frame = CGRect(x: box.minX, y: max(8, box.minY - 30), width: 96, height: 22)
        PanelStyle.canvasTint(0x161719, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
        let crop = pixelCrop
        let text = "\(Int(crop.width)) × \(Int(crop.height))" as NSString
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        text.draw(in: CGRect(x: frame.minX, y: frame.minY + 4, width: frame.width, height: 14),
                  withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                   .foregroundColor: NSColor(srgbRed: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF3 / 255, alpha: 1),
                                   .paragraphStyle: style])
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
        if listOpen { closeList() }
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
            if listOpen { closeList() } else { onCancel?() }
        case 36, 76: // return, enter
            commit()
        default:
            super.keyDown(with: event)
        }
    }
}

private extension CaptureRatio {
    var displayLabel: String { self == .free ? "Free".localized : label }
}

private extension PanelStyle {
    static func canvasTint(_ hex: Int, alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Bar

/// The floating bar: ratio dropdown | divider | Cancel | Capture (Figma 362 × 52).
private final class CaptureBar: NSView {
    static let size = CGSize(width: 346, height: 52)

    var ratioText = "" { didSet { dropdown.value = ratioText } }
    var onToggleList: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCapture: (() -> Void)?

    private let blur = PanelStyle.makeBarBlur()
    private let dropdown = CaptureDropdown(frame: CGRect(x: 8, y: 8, width: 132, height: 36))
    private let cancel = CaptureBarButton(frame: CGRect(x: 156, y: 8, width: 78, height: 36), primary: false)
    private let capture = CaptureBarButton(frame: CGRect(x: 242, y: 8, width: 96, height: 36), primary: true)

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        blur.frame = bounds
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)
        let tint = NSView(frame: bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(srgbRed: 0x16 / 255, green: 0x17 / 255, blue: 0x19 / 255, alpha: 0.92).cgColor
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)

        dropdown.onClick = { [weak self] in self?.onToggleList?() }
        addSubview(dropdown)

        let divider = NSView(frame: CGRect(x: 148, y: 12, width: 1, height: 28))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        addSubview(divider)

        cancel.title = "Cancel".localized
        cancel.onClick = { [weak self] in self?.onCancel?() }
        addSubview(cancel)

        capture.title = "Capture".localized
        capture.icon = NSImage(named: "ToolbarCapture")
        capture.onClick = { [weak self] in self?.onCapture?() }
        addSubview(capture)
    }

    convenience init() {
        self.init(frame: CGRect(origin: .zero, size: CaptureBar.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private func tinted(_ image: NSImage, _ color: NSColor, size: CGSize) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

/// "Ratio  Free  ⌄" (Figma 132 × 36).
private final class CaptureDropdown: NSView {
    var value = "" { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var hovering = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        (hovering ? PanelStyle.canvasTint(0x25262B, alpha: 1) : PanelStyle.canvasTint(0x1D1E22, alpha: 1)).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        ("Ratio".localized as NSString).draw(in: CGRect(x: 12, y: 11, width: 38, height: 14),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular),
                             .foregroundColor: PanelStyle.textTertiary])
        (value as NSString).draw(in: CGRect(x: 50, y: 10, width: 52, height: 16),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                             .foregroundColor: PanelStyle.textPrimary])
        // Figma chevronDown: path "m5 7 4 4 4-4" in an 18-unit box shown at 16 pt,
        // 1.5-unit round stroke, at (width - 26, 10).
        let unit: CGFloat = 16 / 18
        let origin = CGPoint(x: bounds.width - 26, y: 10)
        let chevron = NSBezierPath()
        chevron.move(to: CGPoint(x: origin.x + 5 * unit, y: origin.y + 7 * unit))
        chevron.line(to: CGPoint(x: origin.x + 9 * unit, y: origin.y + 11 * unit))
        chevron.line(to: CGPoint(x: origin.x + 13 * unit, y: origin.y + 7 * unit))
        chevron.lineWidth = 1.5 * unit
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        NSColor(srgbRed: 0xD8 / 255, green: 0xD3 / 255, blue: 0xCE / 255, alpha: 1).setStroke()
        chevron.stroke()
    }
}

/// Cancel (quiet) and Capture (amber primary), 36 high, radius 9.
private final class CaptureBarButton: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var icon: NSImage?
    var onClick: (() -> Void)?
    private let primary: Bool
    private var hovering = false
    private var pressed = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(frame: NSRect, primary: Bool) {
        self.primary = primary
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; pressed = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if inside { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        if primary {
            (hovering ? PanelStyle.accentHover : PanelStyle.warmCue).setFill()
            path.fill()
            if pressed { NSColor.black.withAlphaComponent(0.12).setFill(); path.fill() }
            // Icon + label are centred together, horizontally and vertically.
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: PanelStyle.accentInk]
            let textWidth = ceil((title as NSString).size(withAttributes: attributes).width)
            let iconWidth: CGFloat = icon == nil ? 0 : 16 + 6
            var x = ((bounds.width - iconWidth - textWidth) / 2).rounded()
            if let icon {
                tinted(icon, PanelStyle.accentInk, size: CGSize(width: 16, height: 16))
                    .draw(in: CGRect(x: x, y: 10, width: 16, height: 16),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                x += iconWidth
            }
            (title as NSString).draw(in: CGRect(x: x, y: 10, width: textWidth + 2, height: 16),
                                     withAttributes: attributes)
        } else {
            (hovering ? PanelStyle.canvasTint(0x25262B, alpha: 1) : PanelStyle.canvasTint(0x1D1E22, alpha: 1)).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.12).setStroke()
            path.lineWidth = 1
            path.stroke()
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            (title as NSString).draw(in: CGRect(x: 0, y: 10, width: bounds.width, height: 16),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                 .foregroundColor: PanelStyle.textPrimary,
                                 .paragraphStyle: style])
        }
    }
}

// MARK: - Ratio list

/// The open dropdown: 132 wide, 30 pt rows, 6 pt padding, radius 10.
private final class CaptureRatioList: NSView {
    static let rowHeight: CGFloat = 30
    static let padding: CGFloat = 6
    static let size = CGSize(width: 132,
                             height: padding * 2 + rowHeight * CGFloat(CaptureRatio.allCases.count))

    var selected: CaptureRatio = .free { didSet { needsDisplay = true } }
    var onSelect: ((CaptureRatio) -> Void)?
    private var hovered: CaptureRatio?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self))
    }

    private func ratio(at point: CGPoint) -> CaptureRatio? {
        let index = Int(floor((point.y - Self.padding) / Self.rowHeight))
        let all = CaptureRatio.allCases
        return all.indices.contains(index) ? all[index] : nil
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = ratio(at: convert(event.locationInWindow, from: nil)); needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        if let picked = ratio(at: convert(event.locationInWindow, from: nil)) { onSelect?(picked) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        PanelStyle.canvasTint(0x1C1D21, alpha: 1).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 1
        path.stroke()

        for (index, item) in CaptureRatio.allCases.enumerated() {
            let row = CGRect(x: Self.padding, y: Self.padding + CGFloat(index) * Self.rowHeight,
                             width: bounds.width - Self.padding * 2, height: Self.rowHeight)
            if hovered == item {
                PanelStyle.rowHover.setFill()
                NSBezierPath(roundedRect: row, xRadius: 7, yRadius: 7).fill()
            }
            let isSelected = item == selected
            let label = (item == .free ? "Free".localized : item.label) as NSString
            label.draw(in: CGRect(x: row.minX + 8, y: row.minY + 7, width: row.width - 36, height: 16),
                       withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
                                        .foregroundColor: isSelected ? PanelStyle.warmCue : PanelStyle.textPrimary])
            if isSelected, let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) {
                tinted(check, PanelStyle.warmCue, size: CGSize(width: 14, height: 14))
                    .draw(in: CGRect(x: row.minX + row.width - 24, y: row.minY + 8, width: 14, height: 14),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
    }
}
