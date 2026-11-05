// Headless geometry regression check (does not build or launch Glance):
// Copy this file to /tmp/glance-media-size/main.swift, then compile it with
// clients/macos/Glance/Sources/ScreenManager.swift and run the resulting binary.
import AppKit

let imageMinimum = NSSize(width: 560, height: 360)
let videoMinimum = NSSize(width: 560, height: 488)
let desktop = NSSize(width: 1382, height: 860)
var checks = 0

func check(_ condition: Bool, _ label: String) {
    precondition(condition, label)
    checks += 1
}

let tinyImage = ScreenManager.mediaWindowSize(preferred: NSSize(width: 10, height: 10),
                                             minimum: imageMinimum, maximum: desktop)
check(tinyImage == imageMinimum, "10×10 image keeps usable controls")
let tinyCompare = ScreenManager.mediaWindowSize(preferred: NSSize(width: 22, height: 10),
                                               minimum: videoMinimum, maximum: desktop)
check(tinyCompare == videoMinimum, "two 10×10 videos keep playback controls usable")
let normal = NSSize(width: 800, height: 600)
check(ScreenManager.mediaWindowSize(preferred: normal, minimum: imageMinimum, maximum: desktop) == normal,
      "ordinary image keeps its native window size")

for minimum in [imageMinimum, videoMinimum, NSSize(width: 400, height: 320)] {
    for maximum in [desktop, NSSize(width: 480, height: 300)] {
        for preferred in [NSSize(width: 1, height: 1), NSSize(width: 10, height: 100_000),
                          NSSize(width: 100_000, height: 10), NSSize(width: 7680, height: 4320),
                          NSSize.zero, NSSize(width: CGFloat.nan, height: 10)] {
            let size = ScreenManager.mediaWindowSize(preferred: preferred, minimum: minimum, maximum: maximum)
            check(size.width.isFinite && size.height.isFinite, "finite output")
            check(size.width >= min(minimum.width, maximum.width) &&
                  size.height >= min(minimum.height, maximum.height), "controls have a usable canvas")
            check(size.width <= maximum.width && size.height <= maximum.height, "window fits display")
        }
    }
}
print("PASS: \(checks) media window geometry checks; no UI launched")
