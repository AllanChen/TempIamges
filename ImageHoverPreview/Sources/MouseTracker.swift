import AppKit

class MouseTracker {
    static let mousePositionDidChange = Notification.Name("MouseTracker.mousePositionDidChange")

    private var timer: Timer?
    private var lastPosition: CGPoint = .zero

    var isTracking: Bool {
        return timer != nil
    }

    func startTracking() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.pollMousePosition()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    private func pollMousePosition() {
        let location = NSEvent.mouseLocation

        // Only post if position changed
        if location != lastPosition {
            lastPosition = location

            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }) ?? NSScreen.main else {
                return
            }

            let axX = location.x
            let axY = screen.frame.height - (location.y - screen.frame.minY)
            let cgPoint = CGPoint(x: axX, y: axY)

            NotificationCenter.default.post(
                name: MouseTracker.mousePositionDidChange,
                object: self,
                userInfo: ["position": cgPoint, "screenLocation": location]
            )
        }
    }

    deinit {
        stopTracking()
    }
}