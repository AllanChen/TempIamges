// Checks the capture editor's pure geometry. No UI, no App build. swiftc only treats a file
// named main.swift as top-level code, so compile a copy under that name:
//   mkdir -p /tmp/cg-test && cp scripts/test-capture-geometry.swift /tmp/cg-test/main.swift
//   swiftc Glance/Sources/Capture/CaptureGeometry.swift /tmp/cg-test/main.swift -o /tmp/cg-test/run && /tmp/cg-test/run
import CoreGraphics
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { print("ok   \(name)") } else { failures += 1; print("FAIL \(name) \(detail())") }
}
func near(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.5) -> Bool { abs(a - b) <= eps }
func near(_ a: CGRect, _ b: CGRect, _ eps: CGFloat = 0.5) -> Bool {
    near(a.minX, b.minX, eps) && near(a.minY, b.minY, eps) && near(a.width, b.width, eps) && near(a.height, b.height, eps)
}

// MARK: visibleRect — 4000 × 3000 image in a 1000 × 750 pane (fits exactly)
let img = CGSize(width: 4000, height: 3000)
let pane = CGSize(width: 1000, height: 750)
let whole = CaptureGeometry.visibleRect(imagePixels: img, paneSize: pane, zoom: 1, center: CGPoint(x: 0.5, y: 0.5))
check("fit view shows the whole image", near(whole, CGRect(x: 0, y: 0, width: 4000, height: 3000)), "\(whole)")

let z2 = CaptureGeometry.visibleRect(imagePixels: img, paneSize: pane, zoom: 2, center: CGPoint(x: 0.5, y: 0.5))
check("2x zoom centred shows the middle quarter", near(z2, CGRect(x: 1000, y: 750, width: 2000, height: 1500)), "\(z2)")

// Bottom-origin centre (0.25, 0.25) = lower-left area; in top-left pixels that is y from the bottom half.
let corner = CaptureGeometry.visibleRect(imagePixels: img, paneSize: pane, zoom: 2, center: CGPoint(x: 0.25, y: 0.25))
check("pan to lower-left (bottom-origin) maps to top-left pixels", near(corner, CGRect(x: 0, y: 1500, width: 2000, height: 1500)), "\(corner)")

let beyond = CaptureGeometry.visibleRect(imagePixels: img, paneSize: pane, zoom: 2, center: CGPoint(x: 0, y: 1))
check("a centre beyond the edge is clamped inside the image", near(beyond, CGRect(x: 0, y: 0, width: 2000, height: 1500)), "\(beyond)")

let out = CaptureGeometry.visibleRect(imagePixels: img, paneSize: pane, zoom: 0.5, center: CGPoint(x: 0.5, y: 0.5))
check("zoomed out shows the whole image", near(out, CGRect(x: 0, y: 0, width: 4000, height: 3000)), "\(out)")

// A wide pane around a tall image letterboxes it; the visible area is the whole image.
let tall = CaptureGeometry.visibleRect(imagePixels: CGSize(width: 1000, height: 2000), paneSize: CGSize(width: 1000, height: 500), zoom: 1, center: CGPoint(x: 0.5, y: 0.5))
check("tall image in a wide pane is fully visible", near(tall, CGRect(x: 0, y: 0, width: 1000, height: 2000)), "\(tall)")
let shown = CaptureGeometry.displayedRect(imagePixels: CGSize(width: 1000, height: 2000), paneSize: CGSize(width: 1000, height: 500), zoom: 1)
check("…and sits centred with side bars", near(shown, CGRect(x: 375, y: 0, width: 250, height: 500)), "\(shown)")

// MARK: fit — largest box of a ratio
let area = CGRect(x: 0, y: 0, width: 1200, height: 800)
let r34 = CaptureGeometry.fit(.threeFour, around: CGPoint(x: 600, y: 400), in: area)!
check("3:4 in a landscape area fills the height", near(r34, CGRect(x: 300, y: 0, width: 600, height: 800)), "\(r34)")
let r169 = CaptureGeometry.fit(.sixteenNine, around: CGPoint(x: 600, y: 400), in: area)!
check("16:9 fills the width", near(r169, CGRect(x: 0, y: 62.5, width: 1200, height: 675)), "\(r169)")
let near1 = CaptureGeometry.fit(.square, around: CGPoint(x: 50, y: 50), in: area)!
check("1:1 around a corner is shifted back inside", near(near1, CGRect(x: 0, y: 0, width: 800, height: 800)), "\(near1)")
check("free has no fit", CaptureGeometry.fit(.free, around: .zero, in: area) == nil)
for ratio in CaptureRatio.allCases {
    guard let r = CaptureGeometry.fit(ratio, around: CGPoint(x: 100, y: 700), in: area) else { continue }
    check("fit \(ratio.label) stays inside and keeps its ratio",
          area.contains(r) && near(r.width / r.height, ratio.aspect!, 0.01), "\(r)")
}

// MARK: move
let moved = CaptureGeometry.move(CGRect(x: 100, y: 100, width: 300, height: 200), by: CGPoint(x: 5000, y: -5000), in: area)
check("move is clamped to the area", near(moved, CGRect(x: 900, y: 0, width: 300, height: 200)), "\(moved)")

// MARK: resize, free
let base = CGRect(x: 200, y: 200, width: 400, height: 300)
let free1 = CaptureGeometry.resize(base, handle: .bottomRight, to: CGPoint(x: 900, y: 700), aspect: nil, in: area)
check("free bottom-right keeps the top-left corner", near(free1, CGRect(x: 200, y: 200, width: 700, height: 500)), "\(free1)")
let free2 = CaptureGeometry.resize(base, handle: .left, to: CGPoint(x: 590, y: 0), aspect: nil, in: area)
check("free left cannot pass the minimum width", near(free2.width, CaptureGeometry.minimumSelection) && near(free2.maxX, 600), "\(free2)")
let free3 = CaptureGeometry.resize(base, handle: .topLeft, to: CGPoint(x: -50, y: -50), aspect: nil, in: area)
check("free top-left is clamped to the area", near(free3, CGRect(x: 0, y: 0, width: 600, height: 500)), "\(free3)")

// MARK: resize, locked ratio
let a34: CGFloat = 3.0 / 4.0
let box34 = CGRect(x: 300, y: 100, width: 300, height: 400)
for handle in CaptureHandle.allCases {
    let target = handle.position(on: box34.insetBy(dx: -90, dy: -90))
    let r = CaptureGeometry.resize(box34, handle: handle, to: target, aspect: a34, in: area)
    check("3:4 \(handle) keeps ratio and stays inside", near(r.width / r.height, a34, 0.01) && area.insetBy(dx: -0.01, dy: -0.01).contains(r), "\(r)")
}
let grow = CaptureGeometry.resize(box34, handle: .bottomRight, to: CGPoint(x: 750, y: 560), aspect: a34, in: area)
check("corner grows to cover the drag, anchored top-left",
      near(grow.minX, 300) && near(grow.minY, 100) && near(grow.width, 450) && near(grow.height, 600), "\(grow)")
let edge = CaptureGeometry.resize(box34, handle: .right, to: CGPoint(x: 750, y: 300), aspect: a34, in: area)
check("edge drag scales the other side about the centre",
      near(edge.minX, 300) && near(edge.width, 450) && near(edge.midY, box34.midY), "\(edge)")
let tiny = CaptureGeometry.resize(box34, handle: .bottomRight, to: CGPoint(x: 301, y: 101), aspect: a34, in: area)
check("locked resize respects the minimum", tiny.width >= CaptureGeometry.minimumSelection && tiny.height >= CaptureGeometry.minimumSelection, "\(tiny)")
// A fresh drag starts from a zero-size rect.
let fresh = CaptureGeometry.resize(CGRect(x: 400, y: 300, width: 0, height: 0), handle: .bottomRight, to: CGPoint(x: 700, y: 640), aspect: 1, in: area)
check("new selection with 1:1 is square", near(fresh.width, fresh.height) && near(fresh.minX, 400) && near(fresh.minY, 300), "\(fresh)")

// MARK: selection → pixels
let imageRect = CGRect(x: 100, y: 50, width: 800, height: 600)     // 4000 × 3000 px shown at 0.2 scale
let crop = CaptureGeometry.cropRect(selection: CGRect(x: 300, y: 250, width: 400, height: 300), imageRect: imageRect, imagePixels: img)
check("selection maps to full-resolution pixels", near(crop, CGRect(x: 1000, y: 1000, width: 2000, height: 1500)), "\(crop)")
let full = CaptureGeometry.cropRect(selection: imageRect, imageRect: imageRect, imagePixels: img)
check("whole image selection maps to the whole image", near(full, CGRect(x: 0, y: 0, width: 4000, height: 3000)), "\(full)")
let spill = CaptureGeometry.cropRect(selection: imageRect.insetBy(dx: -50, dy: -50), imageRect: imageRect, imagePixels: img)
check("a selection past the image is clamped", near(spill, CGRect(x: 0, y: 0, width: 4000, height: 3000)), "\(spill)")
let fitRect = CaptureGeometry.aspectFit(CGSize(width: 2000, height: 1000), in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
check("aspect fit letterboxes vertically", near(fitRect, CGRect(x: 0, y: 250, width: 1000, height: 500)), "\(fitRect)")

print(failures == 0 ? "\nall capture geometry checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
