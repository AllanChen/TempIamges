import CoreGraphics

/// Aspect presets offered by the capture bar's dropdown (Figma "Capture Editor").
enum CaptureRatio: CaseIterable {
    case free, square, threeFour, fourThree, nineSixteen, sixteenNine

    /// Width / height; nil for a free-form selection.
    var aspect: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .threeFour: return 3.0 / 4.0
        case .fourThree: return 4.0 / 3.0
        case .nineSixteen: return 9.0 / 16.0
        case .sixteenNine: return 16.0 / 9.0
        }
    }

    /// Text shown in the dropdown. "Free" is localized by the caller.
    var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .threeFour: return "3:4"
        case .fourThree: return "4:3"
        case .nineSixteen: return "9:16"
        case .sixteenNine: return "16:9"
        }
    }
}

enum CaptureHandle: CaseIterable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }

    /// Handle position on `rect` (top-left origin), matching Figma's 8 handles.
    func position(on rect: CGRect) -> CGPoint {
        let x = movesLeft ? rect.minX : (movesRight ? rect.maxX : rect.midX)
        let y = movesTop ? rect.minY : (movesBottom ? rect.maxY : rect.midY)
        return CGPoint(x: x, y: y)
    }
}

/// Pure geometry for the capture editor. Two coordinate systems meet here:
///
///  - the image viewport (AppKit, bottom-left origin, normalized centre in the
///    rotated image), used by `visibleRect` / `displayedRect`;
///  - the editor view (flipped, top-left origin like Figma), used by every
///    selection function. `cropRect` converts to top-left image pixels, which
///    is what `CGImage.cropping(to:)` expects.
enum CaptureGeometry {
    // MARK: - Viewport → image pixels

    /// The part of an image that a viewport currently shows, in image pixels
    /// with a top-left origin (ready for `CGImage.cropping`).
    ///
    /// `imagePixels` is the size of the image as displayed (already rotated).
    /// `zoom` and `center` are the viewport's `zoomRelativeToFit` and
    /// bottom-origin `normalizedCenter`. Mirrors InspectImageViewport's own
    /// maths: rendered size = fit scale × zoom × image size, pan is clamped so
    /// the image never leaves the pane.
    static func visibleRect(imagePixels: CGSize, paneSize: CGSize,
                            zoom: CGFloat, center: CGPoint) -> CGRect {
        guard imagePixels.width > 0, imagePixels.height > 0,
              paneSize.width > 0, paneSize.height > 0 else {
            return CGRect(origin: .zero, size: imagePixels)
        }
        let fit = min(paneSize.width / imagePixels.width, paneSize.height / imagePixels.height)
        let scale = fit * max(zoom, 0.0001)
        let renderedW = imagePixels.width * scale
        let renderedH = imagePixels.height * scale
        let fracW = min(1, paneSize.width / renderedW)
        let fracH = min(1, paneSize.height / renderedH)
        // Bottom-origin normalized rect, clamped inside the image.
        let x0 = min(max(center.x - fracW / 2, 0), 1 - fracW)
        let y0 = min(max(center.y - fracH / 2, 0), 1 - fracH)
        let left = (x0 * imagePixels.width).rounded(.down)
        let top = ((1 - y0 - fracH) * imagePixels.height).rounded(.down)
        let right = min(imagePixels.width, ((x0 + fracW) * imagePixels.width).rounded(.up))
        let bottom = min(imagePixels.height, ((1 - y0) * imagePixels.height).rounded(.up))
        return CGRect(x: max(0, left), y: max(0, top),
                      width: max(1, right - max(0, left)), height: max(1, bottom - max(0, top)))
    }

    /// Where the image sits inside the pane, in pane points with a top-left
    /// origin. Equals the pane when the image overflows it; a centred rect
    /// (letterbox) when the image is smaller on an axis.
    static func displayedRect(imagePixels: CGSize, paneSize: CGSize, zoom: CGFloat) -> CGRect {
        guard imagePixels.width > 0, imagePixels.height > 0 else { return CGRect(origin: .zero, size: paneSize) }
        let fit = min(paneSize.width / imagePixels.width, paneSize.height / imagePixels.height)
        let scale = fit * max(zoom, 0.0001)
        let w = min(paneSize.width, imagePixels.width * scale)
        let h = min(paneSize.height, imagePixels.height * scale)
        return CGRect(x: (paneSize.width - w) / 2, y: (paneSize.height - h) / 2, width: w, height: h)
    }

    // MARK: - Selection (editor coordinates, top-left origin)

    static let minimumSelection: CGFloat = 24

    /// The selection a new editor starts with: the whole image.
    static func initialSelection(in area: CGRect) -> CGRect { area }

    /// Largest box of `ratio` that fits in `area`, centred on `center` and
    /// shifted back inside if the centre was near an edge.
    static func fit(_ ratio: CaptureRatio, around center: CGPoint, in area: CGRect) -> CGRect? {
        guard let aspect = ratio.aspect, area.width > 0, area.height > 0 else { return nil }
        var w = area.width
        var h = w / aspect
        if h > area.height { h = area.height; w = h * aspect }
        var x = center.x - w / 2
        var y = center.y - h / 2
        x = min(max(x, area.minX), area.maxX - w)
        y = min(max(y, area.minY), area.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func move(_ rect: CGRect, by delta: CGPoint, in area: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.x, dy: delta.y)
        moved.origin.x = min(max(moved.origin.x, area.minX), area.maxX - moved.width)
        moved.origin.y = min(max(moved.origin.y, area.minY), area.maxY - moved.height)
        return moved
    }

    /// Resizes `rect` by dragging `handle` to `point`. The opposite corner or
    /// edge stays put. With `aspect` the ratio is locked: a corner grows to
    /// cover the drag, an edge scales the other dimension about the centre.
    /// The result always stays inside `area` and above the minimum size.
    static func resize(_ rect: CGRect, handle: CaptureHandle, to point: CGPoint,
                       aspect: CGFloat?, in area: CGRect) -> CGRect {
        let minS = minimumSelection
        let p = CGPoint(x: min(max(point.x, area.minX), area.maxX),
                        y: min(max(point.y, area.minY), area.maxY))

        guard let aspect else {
            var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
            if handle.movesLeft { left = min(p.x, right - minS) }
            if handle.movesRight { right = max(p.x, left + minS) }
            if handle.movesTop { top = min(p.y, bottom - minS) }
            if handle.movesBottom { bottom = max(p.y, top + minS) }
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }

        let minW = max(minS, minS * aspect)
        if handle.isCorner {
            let anchor = CGPoint(x: handle.movesLeft ? rect.maxX : rect.minX,
                                 y: handle.movesTop ? rect.maxY : rect.minY)
            let dirX: CGFloat = handle.movesLeft ? -1 : 1
            let dirY: CGFloat = handle.movesTop ? -1 : 1
            let dx = max(0, (p.x - anchor.x) * dirX)
            let dy = max(0, (p.y - anchor.y) * dirY)
            var w = max(dx, dy * aspect, minW)
            let availW = dirX > 0 ? area.maxX - anchor.x : anchor.x - area.minX
            let availH = dirY > 0 ? area.maxY - anchor.y : anchor.y - area.minY
            w = min(w, availW, availH * aspect)
            let h = w / aspect
            return CGRect(x: dirX > 0 ? anchor.x : anchor.x - w,
                          y: dirY > 0 ? anchor.y : anchor.y - h, width: w, height: h)
        }
        if handle.movesLeft || handle.movesRight {
            let anchorX = handle.movesLeft ? rect.maxX : rect.minX
            let dirX: CGFloat = handle.movesLeft ? -1 : 1
            var w = max((p.x - anchorX) * dirX, minW)
            let availW = dirX > 0 ? area.maxX - anchorX : anchorX - area.minX
            let cy = rect.midY
            let availH = 2 * min(cy - area.minY, area.maxY - cy)
            w = min(w, availW, availH * aspect)
            let h = w / aspect
            return CGRect(x: dirX > 0 ? anchorX : anchorX - w, y: cy - h / 2, width: w, height: h)
        }
        let anchorY = handle.movesTop ? rect.maxY : rect.minY
        let dirY: CGFloat = handle.movesTop ? -1 : 1
        var h = max((p.y - anchorY) * dirY, minW / aspect)
        let availH = dirY > 0 ? area.maxY - anchorY : anchorY - area.minY
        let cx = rect.midX
        let availW = 2 * min(cx - area.minX, area.maxX - cx)
        h = min(h, availH, availW / aspect)
        let w = h * aspect
        return CGRect(x: cx - w / 2, y: dirY > 0 ? anchorY : anchorY - h, width: w, height: h)
    }

    // MARK: - Selection → pixels

    /// Converts a selection in editor coordinates into a top-left pixel rect
    /// of the frozen image displayed at `imageRect`.
    static func cropRect(selection: CGRect, imageRect: CGRect, imagePixels: CGSize) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return .zero }
        let sx = imagePixels.width / imageRect.width
        let sy = imagePixels.height / imageRect.height
        let x = ((selection.minX - imageRect.minX) * sx).rounded(.down)
        let y = ((selection.minY - imageRect.minY) * sy).rounded(.down)
        let right = ((selection.maxX - imageRect.minX) * sx).rounded(.up)
        let bottom = ((selection.maxY - imageRect.minY) * sy).rounded(.up)
        let clamped = CGRect(x: max(0, x), y: max(0, y),
                             width: min(imagePixels.width, right) - max(0, x),
                             height: min(imagePixels.height, bottom) - max(0, y))
        return CGRect(x: clamped.minX, y: clamped.minY,
                      width: max(1, clamped.width), height: max(1, clamped.height))
    }

    /// Aspect-fit placement of an image of `pixels` size inside `area`.
    static func aspectFit(_ pixels: CGSize, in area: CGRect) -> CGRect {
        guard pixels.width > 0, pixels.height > 0, area.width > 0, area.height > 0 else { return area }
        let scale = min(area.width / pixels.width, area.height / pixels.height)
        let w = pixels.width * scale, h = pixels.height * scale
        return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }
}
