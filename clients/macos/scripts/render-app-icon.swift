#!/usr/bin/env swift
// Renders AppIcon.appiconset from the Glance brand character (Figma "Brand ·
// App Icon" › "AppIcon / B · Peek"): the peeker looking over the frame's rim,
// flat paper on sumi ink. The menu bar uses the same character as a flat
// template glyph (MenuBarCharacterIcon.swift).
//
// Usage (from the repo root):  swift clients/macos/scripts/render-app-icon.swift          # AppIcon.appiconset
//                              swift clients/macos/scripts/render-app-icon.swift --logo   # logo.png (full bleed)
// No third-party dependencies; CoreGraphics only.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = "clients/macos/Glance/Resources/Assets.xcassets/AppIcon.appiconset"
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

/// Fills `path` with a flat colour.
func fill(_ ctx: CGContext, _ path: CGPath, _ hex: String, _ alpha: CGFloat = 1) {
    ctx.setFillColor(color(hex, alpha)); ctx.addPath(path); ctx.fillPath()
}

// Figma "Brand · App Icon" › "AppIcon / B · Peek" (静 Shizuka): the peeker as
// flat paper on sumi ink — a dome head with two ink eyes looking over the
// frame's paper rim, round hands on the rim, one vermilion mark on the frame.
// Fractions are of the squircle side (Figma's 824 pt icon body).
func draw(into ctx: CGContext, pixels: Int) {
    let k = CGFloat(pixels) / canvas
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: k, y: -k)
    ctx.setAllowsAntialiasing(true)

    let s = squircle
    let o = (canvas - s) / 2
    func u(_ v: CGFloat) -> CGFloat { v / 824 * s }
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: o + u(x), y: o + u(y), width: u(w), height: u(h)) }
    func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

    let paper = "#EAE7E0", ink = "#151514", well = "#2E2E2B", shu = "#C65A40"

    // Ink body with a faint top-edge hairline.
    let bodyRect = CGRect(x: o, y: o, width: s, height: s)
    let body = rounded(bodyRect, s * cornerRatio)
    fill(ctx, body, ink)
    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    ctx.setStrokeColor(color("#FFFFFF", 0.07)); ctx.setLineWidth(u(3))
    ctx.addPath(rounded(bodyRect.insetBy(dx: u(1.5), dy: u(1.5)), s * cornerRatio)); ctx.strokePath()
    ctx.restoreGState()

    // Head: the upper half of a disc resting on the frame's rim.
    let head = CGMutablePath()
    head.addArc(center: CGPoint(x: o + u(412), y: o + u(490)), radius: u(200),
                startAngle: .pi, endAngle: 0, clockwise: false)
    head.closeSubpath()
    fill(ctx, head, paper)
    for cx in [346.0, 478.0] as [CGFloat] {
        fill(ctx, CGPath(ellipseIn: R(cx - 30, 382, 60, 60), transform: nil), ink)
    }

    // Frame (the photo well) with its paper rim, hands on the rim, and the mark.
    fill(ctx, rounded(R(112, 490, 600, 232), u(32)), well)
    fill(ctx, rounded(R(112, 490, 600, 14), u(7)), paper)
    for x in [194.0, 538.0] as [CGFloat] {
        fill(ctx, rounded(R(x, 466, 92, 44), u(22)), paper)
    }
    fill(ctx, CGPath(ellipseIn: R(642, 652, 36, 36), transform: nil), shu)
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
    write(render(pixels: Int(canvas)), to: "design/marketing/brand-assets/logo.png")
    print("wrote design/marketing/brand-assets/logo.png (1024×1024, full bleed)")
} else {
    for entry in sizes {
        let px = entry.points * entry.scale
        write(render(pixels: px), to: "\(outputDirectory)/\(entry.file)")
        print("wrote \(entry.file) (\(px)×\(px))")
    }
}
