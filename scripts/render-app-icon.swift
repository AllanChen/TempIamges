#!/usr/bin/env swift
// Renders AppIcon.appiconset from the Glance brand character (Figma "App Logo /
// Tangible", concept B): the peeker looking over a half-developed photo print.
// Geometry mirrors the plugin's `tangibleCharacterIcon`; the menu bar uses the
// same character as a flat template glyph (MenuBarCharacterIcon.swift).
//
// Usage (from the repo root):  swift scripts/render-app-icon.swift          # AppIcon.appiconset
//                              swift scripts/render-app-icon.swift --logo   # logo.png (full bleed)
// No third-party dependencies; CoreGraphics only.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = "Glance/Resources/Assets.xcassets/AppIcon.appiconset"
let sizes: [(points: Int, scale: Int, file: String)] = [
    (16, 1, "icon_16x16.png"), (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"), (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"), (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"), (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"), (512, 2, "icon_512x512@2x.png"),
]

// macOS icon grid: the squircle occupies 80% of the canvas (matches the
// previous icon), the glyph sits in the 824/1024 safe area of the squircle.
let canvas: CGFloat = 1024
// `--logo` renders the full-bleed brand image (logo.png) instead of the icon set.
let logoMode = CommandLine.arguments.contains("--logo")
let squircle: CGFloat = logoMode ? canvas : canvas * 0.8
let cornerRatio: CGFloat = 0.2237
let glyphInset: CGFloat = 824.0 / 1024.0

func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                   components: [CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255,
                                CGFloat(v & 0xFF) / 255, alpha])!
}

func gradient(_ hexes: [String], alpha: CGFloat = 1) -> CGGradient {
    let colors = hexes.map { color($0, alpha) } as CFArray
    let locations = (0..<hexes.count).map { CGFloat($0) / CGFloat(max(1, hexes.count - 1)) }
    return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: locations)!
}

let amber = ["#E8A87C", "#D4A574", "#C8AA82"]
let amberLight = ["#F0B896", "#E8C87C"]

/// Fills `path` with a top-left → bottom-right gradient across `box`.
func fill(_ ctx: CGContext, _ path: CGPath, _ grad: CGGradient, box: CGRect) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: box.minX, y: box.minY),
                           end: CGPoint(x: box.maxX, y: box.maxY), options: [])
    ctx.restoreGState()
}

func stroke(_ ctx: CGContext, _ path: CGPath, width: CGFloat, _ grad: CGGradient, box: CGRect,
            cap: CGLineCap = .butt) {
    let outline = path.copy(strokingWithWidth: width, lineCap: cap, lineJoin: .round, miterLimit: 10)
    fill(ctx, outline, grad, box: box)
}

// Concept B from Figma "App Logo / Tangible": the Glance peeker — a round
// amber character looking over a photo print that is developed on the left
// and still grey on the right, hands on the frame edge. No hat.
func draw(into ctx: CGContext, pixels: Int) {
    let k = CGFloat(pixels) / canvas
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: k, y: -k)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let s = squircle
    let o = (canvas - s) / 2
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: o + x * s, y: o + y * s, width: w * s, height: h * s) }
    func fillGrad(_ path: CGPath, _ grad: CGGradient, _ box: CGRect, vertical: Bool = false) {
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        let start = CGPoint(x: box.minX, y: box.minY)
        let end = vertical ? CGPoint(x: box.minX, y: box.maxY) : CGPoint(x: box.maxX, y: box.maxY)
        ctx.drawLinearGradient(grad, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    // Shadow offsets are in base space (unflipped): negative y drops downward.
    func withShadow(_ dy: CGFloat, _ blur: CGFloat, _ alpha: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -dy * s * k), blur: blur * s * k, color: color("#000000", alpha))
        body()
        ctx.restoreGState()
    }
    func ellipsePath(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }
    func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
    let amberHead = gradient(["#F0B896", "#E8C87C", "#D4A574"])

    // Matte body.
    let bodyRect = R(0, 0, 1, 1)
    let body = rounded(bodyRect, s * cornerRatio)
    fillGrad(body, gradient(["#1A1B1F", "#0A0A0C"]), bodyRect, vertical: true)
    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    // Top-edge hairline of light.
    ctx.setStrokeColor(color("#FFFFFF", 0.07)); ctx.setLineWidth(s * 0.008)
    ctx.addPath(rounded(bodyRect.insetBy(dx: s * 0.004, dy: s * 0.004), s * cornerRatio)); ctx.strokePath()
    ctx.restoreGState()

    // Head (behind the frame), highlight.
    let hd = 0.50
    let hx = 0.5 - hd / 2, hy = 0.17
    let headRect = R(hx, hy, hd, hd)
    withShadow(0.02, 0.04, 0.45) { fillGrad(ellipsePath(headRect), amberHead, headRect) }
    ctx.setFillColor(color("#FFFFFF", 0.35))
    ctx.fillEllipse(in: R(hx + hd * 0.18, hy + hd * 0.10, hd * 0.34, hd * 0.14))

    // Eyes: big, low, close together; two glints each.
    let ey = hy + hd * 0.50, ew = 0.115, eh = 0.135
    for cx in [0.5 - 0.075, 0.5 + 0.075] {
        ctx.setFillColor(color("#FFF8F0"))
        ctx.fillEllipse(in: R(cx - ew / 2, ey - eh / 2, ew, eh))
        ctx.setFillColor(color("#15110F"))
        ctx.fillEllipse(in: R(cx - ew * 0.30, ey - eh * 0.22, ew * 0.60, eh * 0.62))
        ctx.setFillColor(color("#FFFFFF"))
        ctx.fillEllipse(in: R(cx - ew * 0.22, ey - eh * 0.18, ew * 0.22, ew * 0.22))
        ctx.fillEllipse(in: R(cx + ew * 0.06, ey + eh * 0.12, ew * 0.10, ew * 0.10))
    }
    // Blush and a tiny open-mouth smile.
    ctx.setFillColor(color("#F07A6A", 0.35))
    for cx in [0.5 - 0.17, 0.5 + 0.17] { ctx.fillEllipse(in: R(cx - 0.045, ey + eh * 0.25, 0.09, 0.05)) }
    ctx.setFillColor(color("#2A1614")); ctx.fillEllipse(in: R(0.5 - 0.022, ey + eh * 0.55, 0.044, 0.03))
    ctx.setFillColor(color("#E8705F")); ctx.fillEllipse(in: R(0.5 - 0.012, ey + eh * 0.55 + 0.013, 0.024, 0.014))

    // Photo well and the print.
    let fx = 0.15, fy = 0.46, fw = 0.70, fh = 0.40, fr = 0.07, split = 0.55
    ctx.setFillColor(color("#060607"))
    ctx.addPath(rounded(R(fx - 0.012, fy - 0.012, fw + 0.024, fh + 0.024), (fr + 0.012) * s)); ctx.fillPath()
    let photoRect = R(fx, fy, fw, fh)
    let photo = rounded(photoRect, fr * s)
    func scene(_ clip: CGPath, sun: String, far: String, near: String) {
        ctx.saveGState(); ctx.addPath(clip); ctx.clip()
        ctx.setFillColor(color(sun)); ctx.fillEllipse(in: CGRect(x: photoRect.minX + photoRect.width * 0.62, y: photoRect.minY + photoRect.height * 0.18, width: photoRect.height * 0.26, height: photoRect.height * 0.26))
        ctx.setFillColor(color(far)); ctx.fillEllipse(in: CGRect(x: photoRect.minX - photoRect.width * 0.15, y: photoRect.minY + photoRect.height * 0.55, width: photoRect.width * 0.9, height: photoRect.height * 0.6))
        ctx.setFillColor(color(near)); ctx.fillEllipse(in: CGRect(x: photoRect.minX + photoRect.width * 0.35, y: photoRect.minY + photoRect.height * 0.7, width: photoRect.width * 1.0, height: photoRect.height * 0.6))
        ctx.restoreGState()
    }
    ctx.setFillColor(color("#2B2D33")); ctx.addPath(photo); ctx.fillPath()
    scene(photo, sun: "#4A4C53", far: "#24262B", near: "#1B1D21")
    // Developed half.
    let devClip = CGMutablePath(); devClip.addRect(CGRect(x: photoRect.minX, y: photoRect.minY, width: photoRect.width * split, height: photoRect.height))
    ctx.saveGState(); ctx.addPath(devClip); ctx.clip()
    fillGrad(photo, gradient(["#F2C9A2", "#C98A62", "#5A3226"]), photoRect, vertical: true)
    scene(photo, sun: "#FFE3B8", far: "#8C4F3A", near: "#3B221C")
    ctx.restoreGState()
    // Print edge.
    ctx.setStrokeColor(color("#FFFFFF", 0.10)); ctx.setLineWidth(s * 0.004); ctx.addPath(photo); ctx.strokePath()
    // Slider line.
    withShadow(0, 0.008, 0.5) {
        ctx.setFillColor(color("#FFFFFF", 0.85))
        ctx.addPath(rounded(R(fx + fw * split - 0.006, fy, 0.012, fh), 0.006 * s)); ctx.fillPath()
    }
    // Hands on the frame edge, with finger bumps.
    for cx in [0.5 - 0.20, 0.5 + 0.20] {
        let hand = R(cx - 0.06, fy - 0.055, 0.12, 0.09)
        withShadow(0.008, 0.014, 0.4) { fillGrad(ellipsePath(hand), amberHead, hand) }
        ctx.setFillColor(color("#F0B896"))
        for i in 0..<3 { ctx.fillEllipse(in: R(cx - 0.045 + Double(i) * 0.034, fy - 0.005, 0.03, 0.03)) }
    }
}

func render(pixels: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(into: ctx, pixels: pixels)
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(path)") }
}

if logoMode {
    write(render(pixels: Int(canvas)), to: "logo.png")
    print("wrote logo.png (1024×1024, full bleed)")
} else {
    for entry in sizes {
        let px = entry.points * entry.scale
        write(render(pixels: px), to: "\(outputDirectory)/\(entry.file)")
        print("wrote \(entry.file) (\(px)×\(px))")
    }
}
