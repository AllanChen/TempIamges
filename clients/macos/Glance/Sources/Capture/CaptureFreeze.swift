import AppKit

/// What one image viewport shows right now, with enough detail to re-render it
/// from the original pixels instead of the screen: the capture keeps the
/// image's full resolution, not the display's.
struct CapturePane {
    let image: NSImage
    /// View-only quarter-turns (clockwise) and flips applied by the viewport.
    let quarters: Int
    let flipX: Bool
    let flipY: Bool
    /// The viewport's drawing area in points, and its zoom / bottom-origin centre.
    let paneSize: CGSize
    let zoom: CGFloat
    let center: CGPoint
}

/// Builds the frozen picture the capture editor works on: the view as the user
/// sees it (zoom, pan, rotation, compare layout), rendered at original
/// resolution.
enum CaptureFreeze {
    /// Longest side of a frozen composite. Bounds memory for very large images.
    static let maxSide: CGFloat = 12_000

    // MARK: Orientation and crop

    /// The pane's image as displayed: flips first (they act on the image's own
    /// axes), then clockwise quarter-turns, matching the viewport's layer
    /// transform. Returns the original CGImage untouched when nothing is applied.
    static func oriented(_ pane: CapturePane) -> CGImage? {
        guard var cg = pane.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        if pane.flipX || pane.flipY, let flipped = flip(cg, horizontal: pane.flipX, vertical: pane.flipY) {
            cg = flipped
        }
        let quarters = ((pane.quarters % 4) + 4) % 4
        guard quarters != 0 else { return cg }
        let wrapper = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        return ImageExporter.cgImage(from: wrapper, rotatedQuarters: quarters)
    }

    /// The part of the pane's image that the viewport currently shows, plus
    /// where that part sits in the pane (points, top-left origin).
    static func visibleCrop(of pane: CapturePane) -> (image: CGImage, displayed: CGRect)? {
        guard let full = oriented(pane) else { return nil }
        let pixels = CGSize(width: full.width, height: full.height)
        let rect = CaptureGeometry.visibleRect(imagePixels: pixels, paneSize: pane.paneSize,
                                               zoom: pane.zoom, center: pane.center)
        guard let crop = full.cropping(to: rect) else { return nil }
        let displayed = CaptureGeometry.displayedRect(imagePixels: pixels, paneSize: pane.paneSize, zoom: pane.zoom)
        return (crop, displayed)
    }

    // MARK: Layouts

    /// One image: exactly what its viewport shows.
    static func single(_ pane: CapturePane) -> CGImage? {
        visibleCrop(of: pane)?.image
    }

    /// Compare ▸ Side by side: both panes next to each other, scaled to a
    /// common height, with the same 2 px divider as the window.
    static func sideBySide(_ left: CapturePane, _ right: CapturePane) -> CGImage? {
        guard let a = visibleCrop(of: left)?.image, let b = visibleCrop(of: right)?.image else { return nil }
        var height = CGFloat(max(a.height, b.height))
        var aWidth = CGFloat(a.width) * height / CGFloat(a.height)
        var bWidth = CGFloat(b.width) * height / CGFloat(b.height)
        let gap: CGFloat = 2
        var scale = min(1, maxSide / max(aWidth + gap + bWidth, height))
        scale = max(scale, 0.0001)
        height *= scale; aWidth *= scale; bWidth *= scale
        let width = aWidth + gap * scale + bWidth
        guard let context = makeContext(width: Int(ceil(width)), height: Int(ceil(height))) else { return nil }
        fill(context, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(a, in: CGRect(x: 0, y: 0, width: aWidth, height: height))
        context.draw(b, in: CGRect(x: aWidth + gap * scale, y: 0, width: bWidth, height: height))
        return context.makeImage()
    }

    /// Compare ▸ Slider: image A fills the picture, image B covers the part
    /// left of the divider. `fraction` is the divider's position across the
    /// pane (0…1); it is converted to the visible image so the divider lands
    /// on the same content as on screen, even when the image is letterboxed.
    static func slider(base: CapturePane, overlay: CapturePane, fraction: CGFloat) -> CGImage? {
        guard let a = visibleCrop(of: base), let b = visibleCrop(of: overlay) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(a.image.width, a.image.height)))
        let width = max(1, (CGFloat(a.image.width) * scale).rounded(.up))
        let height = max(1, (CGFloat(a.image.height) * scale).rounded(.up))
        guard let context = makeContext(width: Int(width), height: Int(height)) else { return nil }
        fill(context, width: width, height: height)
        context.interpolationQuality = .high
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        drawAspectFit(a.image, in: canvas, context: context)
        // Divider position in the displayed image of pane A, as 0…1.
        let paneSplit = min(max(fraction, 0), 1) * base.paneSize.width
        let shown = a.displayed
        let relative = shown.width > 0 ? min(max((paneSplit - shown.minX) / shown.width, 0), 1) : fraction
        let split = relative * width
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: split, height: height))
        drawAspectFit(b.image, in: canvas, context: context)
        context.restoreGState()
        context.setFillColor(PanelStyle.textPrimary.withAlphaComponent(0.82).cgColor)
        context.fill(CGRect(x: max(0, split - 1), y: 0, width: 2, height: height))
        return context.makeImage()
    }

    /// A video frame (or a composite of frames) handed over as an NSImage.
    static func frame(_ image: NSImage) -> CGImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let longest = CGFloat(max(cg.width, cg.height))
        guard longest > maxSide else { return cg }
        let scale = maxSide / longest
        return resized(cg, to: CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale))
    }

    // MARK: Drawing helpers

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func fill(_ context: CGContext, width: CGFloat, height: CGFloat) {
        context.setFillColor(PanelStyle.imageCanvas.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func drawAspectFit(_ image: CGImage, in rect: CGRect, context: CGContext) {
        let size = CGSize(width: image.width, height: image.height)
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        context.draw(image, in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    private static func flip(_ image: CGImage, horizontal: Bool, vertical: Bool) -> CGImage? {
        guard let context = makeContext(width: image.width, height: image.height) else { return nil }
        context.translateBy(x: horizontal ? CGFloat(image.width) : 0, y: vertical ? CGFloat(image.height) : 0)
        context.scaleBy(x: horizontal ? -1 : 1, y: vertical ? -1 : 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let context = makeContext(width: max(1, Int(size.width.rounded())), height: max(1, Int(size.height.rounded()))) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
