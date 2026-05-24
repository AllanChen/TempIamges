import AppKit
import CoreGraphics

class KeyboardMonitor: NSObject {
    static let previewModeDidActivate = Notification.Name("KeyboardMonitor.previewModeDidActivate")
    static let previewModeDidDeactivate = Notification.Name("KeyboardMonitor.previewModeDidDeactivate")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cmdHeld: Bool = false
    private var shiftHeld: Bool = false
    private var optionHeld: Bool = false
    private var controlHeld: Bool = false
    private var activeKeyCodes: Set<UInt16> = []
    private var wasPreviewModeActive: Bool = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: .preferencesDidChange,
            object: nil
        )
        // Reset modifier state on wake to prevent stale events after sleep.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func preferencesChanged() {
        checkPreviewModeStateChanged()
    }

    @objc private func systemDidWake() {
        cmdHeld     = false
        shiftHeld   = false
        optionHeld  = false
        controlHeld = false
        activeKeyCodes.removeAll()
        if wasPreviewModeActive {
            wasPreviewModeActive = false
            Logger.info("KeyboardMonitor: System woke — forcing preview mode DEACTIVATED")
            NotificationCenter.default.post(name: KeyboardMonitor.previewModeDidDeactivate, object: self)
        }
    }

    var previewModeActive: Bool {
        let prefs = Preferences.shared
        let required = prefs.effectiveModifiers
        guard !required.isEmpty else { return false }
        if required.contains(.option)  && !optionHeld  { return false }
        if required.contains(.control) && !controlHeld { return false }
        if required.contains(.command) && !cmdHeld     { return false }
        if required.contains(.shift)   && !shiftHeld   { return false }
        // Combo hotkey: also require the specific regular key to be held.
        if let keyCode = prefs.customHotkeyKeyCode {
            return activeKeyCodes.contains(keyCode)
        }
        return true
    }

    func startMonitoring() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
                                     | (1 << CGEventType.keyDown.rawValue)
                                     | (1 << CGEventType.keyUp.rawValue)

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
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .flagsChanged:
            let flags = event.flags
            let prevCmd = cmdHeld
            let prevShift = shiftHeld
            let prevOpt = optionHeld
            let prevCtrl = controlHeld

            cmdHeld     = flags.contains(.maskCommand)
            shiftHeld   = flags.contains(.maskShift)
            optionHeld  = flags.contains(.maskAlternate)
            controlHeld = flags.contains(.maskControl)

            if cmdHeld != prevCmd || shiftHeld != prevShift
                || optionHeld != prevOpt || controlHeld != prevCtrl {
                Logger.info("KeyboardMonitor: Cmd=\(cmdHeld) Shift=\(shiftHeld) Opt=\(optionHeld) Ctrl=\(controlHeld)")
                checkPreviewModeStateChanged()
            }

        case .keyDown:
            activeKeyCodes.insert(keyCode)
            checkPreviewModeStateChanged()

        case .keyUp:
            activeKeyCodes.remove(keyCode)
            checkPreviewModeStateChanged()

        default:
            break
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
        NotificationCenter.default.removeObserver(self)
        stopMonitoring()
    }
}
