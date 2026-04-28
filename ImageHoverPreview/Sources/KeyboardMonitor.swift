import AppKit
import CoreGraphics

class KeyboardMonitor: NSObject {
    static let previewModeDidActivate = Notification.Name("KeyboardMonitor.previewModeDidActivate")
    static let previewModeDidDeactivate = Notification.Name("KeyboardMonitor.previewModeDidDeactivate")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cmdHeld: Bool = false
    private var shiftHeld: Bool = false
    private var wasPreviewModeActive: Bool = false

    var previewModeActive: Bool {
        return cmdHeld && shiftHeld
    }

    func startMonitoring() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handleEvent(proxy: proxy, type: type, event: event)
            return Unmanaged.passRetained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            Logger.info("KeyboardMonitor: Failed to create event tap")
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        guard let runLoopSource = runLoopSource else {
            Logger.info("KeyboardMonitor: Failed to create run loop source")
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        Logger.info("KeyboardMonitor: Event tap created and enabled successfully")

        return true
    }

    func stopMonitoring() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) {
        if type == .flagsChanged {
            let flags = event.flags
            let prevCmdHeld = cmdHeld
            let prevShiftHeld = shiftHeld

            cmdHeld = flags.contains(.maskCommand)
            shiftHeld = flags.contains(.maskShift)

            if cmdHeld != prevCmdHeld || shiftHeld != prevShiftHeld {
                Logger.info("KeyboardMonitor: Cmd=\(cmdHeld), Shift=\(shiftHeld)")
                checkPreviewModeStateChanged()
            }
        }
    }

    private func checkPreviewModeStateChanged() {
        let isActive = previewModeActive

        if isActive != wasPreviewModeActive {
            wasPreviewModeActive = isActive

            if isActive {
                Logger.info("KeyboardMonitor: Preview mode ACTIVATED")
                NotificationCenter.default.post(name: KeyboardMonitor.previewModeDidActivate, object: self)
            } else {
                Logger.info("KeyboardMonitor: Preview mode DEACTIVATED")
                NotificationCenter.default.post(name: KeyboardMonitor.previewModeDidDeactivate, object: self)
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
