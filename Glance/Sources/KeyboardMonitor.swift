import AppKit
import CoreGraphics

/// Watches the global keyboard for the activation hotkey via a `CGEventTap`.
///
/// An active session-level head-insert tap sees every keystroke *before* the
/// focused app, and the WindowServer blocks delivery of each key until the
/// callback returns. Therefore the tap MUST live on its own thread with its own
/// run loop — if it ran on the main run loop, any main-thread stall (layout,
/// synchronous I/O, a busy timer) would freeze keyboard input system-wide.
///
/// The callback only updates cheap modifier state and hands the event straight
/// back; activate/deactivate notifications are posted asynchronously to the main
/// thread so the callback always returns immediately.
final class KeyboardMonitor: NSObject {
    static let previewModeDidActivate = Notification.Name("KeyboardMonitor.previewModeDidActivate")
    static let previewModeDidDeactivate = Notification.Name("KeyboardMonitor.previewModeDidDeactivate")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Dedicated tap thread + its run loop. Keeping the tap off the main run loop
    // is what prevents a busy main thread from blocking all keyboard input.
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    // Hotkey/modifier state. Read and written from both the tap thread and the
    // main thread (preference + wake notifications), so guarded by `stateLock`.
    private let stateLock = NSLock()
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
        stateLock.lock()
        let change = stateChangeLocked()
        stateLock.unlock()
        postIfChanged(change)
    }

    @objc private func systemDidWake() {
        stateLock.lock()
        cmdHeld     = false
        shiftHeld   = false
        optionHeld  = false
        controlHeld = false
        activeKeyCodes.removeAll()
        let wasActive = wasPreviewModeActive
        wasPreviewModeActive = false
        stateLock.unlock()

        if wasActive {
            Logger.info("KeyboardMonitor: System woke — forcing preview mode DEACTIVATED")
            postOnMain(KeyboardMonitor.previewModeDidDeactivate)
        }
    }

    /// Current activation state. Locks because it reads the shared modifier set.
    var previewModeActive: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return previewModeActiveLocked()
    }

    /// `stateLock` must be held by the caller.
    private func previewModeActiveLocked() -> Bool {
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
        guard eventTap == nil else { return true }

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
                                     | (1 << CGEventType.keyDown.rawValue)
                                     | (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()

            // The system disables the tap if a callback runs too long or on
            // certain user input; re-enable it so the hotkey keeps working.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let discard = monitor.handleEvent(type: type, event: event)
            return discard ? nil : Unmanaged.passUnretained(event)
        }

        // Create the tap on the calling thread so we can report success now…
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.info("KeyboardMonitor: Failed to create event tap")
            return false
        }
        eventTap = tap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard runLoopSource != nil else {
            Logger.info("KeyboardMonitor: Failed to create run loop source")
            eventTap = nil
            return false
        }

        // …but service it on a dedicated thread so a busy main thread can never
        // stall keyboard delivery.
        let thread = Thread { [weak self] in
            self?.runTapThread()
        }
        thread.name = "com.glance.keyboard-tap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()

        Logger.info("KeyboardMonitor: Event tap created; servicing on dedicated thread")
        return true
    }

    /// Entry point for the dedicated tap thread: bind the source to this
    /// thread's run loop and keep it spinning until the thread is cancelled.
    private func runTapThread() {
        guard let source = runLoopSource, let tap = eventTap else { return }
        let runLoop = CFRunLoopGetCurrent()
        tapRunLoop = runLoop
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Logger.info("KeyboardMonitor: Tap run loop started")

        // Wake every 0.5s to re-check the cancel flag; the tap source wakes the
        // loop on its own whenever an event arrives.
        while !Thread.current.isCancelled {
            CFRunLoopRunInMode(.defaultMode, 0.5, false)
        }
        Logger.info("KeyboardMonitor: Tap run loop stopped")
    }

    func stopMonitoring() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        tapThread?.cancel()
        if let tapRunLoop = tapRunLoop {
            CFRunLoopStop(tapRunLoop)   // wake the loop so it observes the cancel
        }
        eventTap = nil
        runLoopSource = nil
        tapThread = nil
        tapRunLoop = nil
    }

    /// Runs on the dedicated tap thread. Keep this cheap: update state, post the
    /// activate/deactivate notification asynchronously, and return at once.
    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        var discard = false
        var change: Bool?

        stateLock.lock()
        switch type {
        case .flagsChanged:
            let flags = event.flags
            cmdHeld     = flags.contains(.maskCommand)
            shiftHeld   = flags.contains(.maskShift)
            optionHeld  = flags.contains(.maskAlternate)
            controlHeld = flags.contains(.maskControl)
            change = stateChangeLocked()

        case .keyDown:
            let previouslyActive = previewModeActiveLocked()
            activeKeyCodes.insert(keyCode)
            change = stateChangeLocked()
            if !previouslyActive && previewModeActiveLocked() && Preferences.shared.usesComboHotkey {
                discard = true
            }

        case .keyUp:
            activeKeyCodes.remove(keyCode)
            change = stateChangeLocked()

        default:
            break
        }
        stateLock.unlock()

        postIfChanged(change)
        return discard
    }

    /// `stateLock` must be held. Returns the new activation state if it changed
    /// since the last check (updating `wasPreviewModeActive`), otherwise nil.
    private func stateChangeLocked() -> Bool? {
        let isActive = previewModeActiveLocked()
        guard isActive != wasPreviewModeActive else { return nil }
        wasPreviewModeActive = isActive
        return isActive
    }

    private func postIfChanged(_ change: Bool?) {
        guard let isActive = change else { return }
        if isActive {
            Logger.info("KeyboardMonitor: Preview mode ACTIVATED")
            postOnMain(KeyboardMonitor.previewModeDidActivate)
        } else {
            Logger.info("KeyboardMonitor: Preview mode DEACTIVATED")
            postOnMain(KeyboardMonitor.previewModeDidDeactivate)
        }
    }

    private func postOnMain(_ name: Notification.Name) {
        DispatchQueue.main.async { [weak self] in
            NotificationCenter.default.post(name: name, object: self)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMonitoring()
    }
}
