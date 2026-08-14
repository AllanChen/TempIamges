import AppKit
import ApplicationServices
import CoreGraphics

struct SelectionResult {
    let text: String
    let bounds: CGRect?  // AX screen coords (top-left origin, y-down). nil when unavailable.
}

class SelectedTextExtractor {
    func extractSelection(completion: @escaping (SelectionResult?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if let axResult = self.readViaAXWithTimeout(timeout: 1.0) {
                DispatchQueue.main.async { completion(axResult) }
                return
            }

            Logger.info("SelectedTextExtractor: AX yielded nothing or timed out, trying clipboard")

            if let clipboardResult = self.readViaClipboard() {
                DispatchQueue.main.async { completion(clipboardResult) }
                return
            }

            DispatchQueue.main.async { completion(nil) }
        }
    }

    func extractSelection() -> SelectionResult? {
        if let result = readViaAX() {
            return result
        }
        Logger.info("SelectedTextExtractor: AX yielded nothing, trying clipboard")
        return readViaClipboard()
    }

    // Convenience kept for callers that only need the string.
    func extractSelectedText() -> String? {
        return extractSelection()?.text
    }

    func readClipboardDirectly(completion: @escaping (SelectionResult?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let result = self.readClipboardDirectly()
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Cursor hit-test (read the text under the mouse, any app)

    /// Reads the accessibility text of the UI element directly under the given
    /// screen point (Cocoa coords, bottom-left origin, y-up). Works in any app
    /// whose AX tree exposes the element (VSCode/browser/Finder/native views).
    /// Terminals and self-drawn canvases usually return nothing — callers should
    /// fall back to selection/clipboard.
    ///
    /// Runs a blocking AX read, so call it off the main thread.
    func extractTextAtCursor(at screenPoint: CGPoint) -> SelectionResult? {
        // AX uses top-left origin, y-down. Convert using the screen that
        // actually contains the point so multi-monitor setups map correctly
        // (NSScreen.main is the key-window screen, not necessarily the one the
        // cursor is on).
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) }
            ?? NSScreen.main
        guard let screen = screen else {
            Logger.info("SelectedTextExtractor: no screen for cursor point \(screenPoint)")
            return nil
        }
        // Flip within the frame of the containing screen. `maxY` of that frame is
        // the global top edge of the screen in Cocoa space; subtracting the point
        // yields the AX (y-down) coordinate.
        let axY = screen.frame.maxY - screenPoint.y

        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let hitResult = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(screenPoint.x),
            Float(axY),
            &elementRef
        )
        guard hitResult == .success, let element = elementRef else {
            Logger.info("SelectedTextExtractor: no AX element at cursor (status=\(hitResult.rawValue))")
            return nil
        }

        let attributes: [String] = [
            kAXValueAttribute as String,
            kAXDescriptionAttribute as String,
            kAXTitleAttribute as String,
            kAXRoleDescriptionAttribute as String,
        ]
        for attr in attributes {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
                  let raw = value,
                  CFGetTypeID(raw) == CFStringGetTypeID() else {
                continue
            }
            let text = (raw as! CFString) as String
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Logger.info("SelectedTextExtractor: cursor text via \(attr)='\(trimmed)'")
                return SelectionResult(text: trimmed, bounds: nil)
            }
        }
        Logger.info("SelectedTextExtractor: AX element at cursor had no usable text")
        return nil
    }

    // MARK: - AX path (native Cocoa apps)

    private func readViaAXWithTimeout(timeout: TimeInterval) -> SelectionResult? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: SelectionResult?
        DispatchQueue.global(qos: .userInitiated).async {
            result = self.readViaAX()
            semaphore.signal()
        }
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            Logger.info("SelectedTextExtractor: AX read timed out after \(timeout)s")
            return nil
        }
        return result
    }

    private func readViaAX() -> SelectionResult? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusResult == .success,
              let raw = focusedElement,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            Logger.info("SelectedTextExtractor: No focused element (status=\(focusResult.rawValue))")
            return nil
        }
        let element = raw as! AXUIElement

        var selected: CFTypeRef?
        let selResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selected
        )
        guard selResult == .success,
              let val = selected,
              CFGetTypeID(val) == CFStringGetTypeID() else {
            Logger.info("SelectedTextExtractor: kAXSelectedText unavailable (status=\(selResult.rawValue))")
            return nil
        }

        let text = (val as! CFString) as String
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.info("SelectedTextExtractor: AX selected text empty")
            return nil
        }

        let bounds = readSelectionBounds(element: element)
        Logger.info("SelectedTextExtractor: AX selected='\(trimmed)' bounds=\(bounds.map { "\($0)" } ?? "nil")")
        return SelectionResult(text: trimmed, bounds: bounds)
    }

    private func readSelectionBounds(element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard rangeResult == .success,
              let rangeVal = rangeRef,
              CFGetTypeID(rangeVal) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &range), range.length > 0 else {
            return nil
        }

        var rangeForParam = range
        guard let rangeAxValue = AXValueCreate(.cfRange, &rangeForParam) else {
            return nil
        }
        var boundsRef: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeAxValue,
            &boundsRef
        )
        guard boundsResult == .success,
              let boundsVal = boundsRef,
              CFGetTypeID(boundsVal) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect),
              rect.width > 0, rect.height > 0 else {
            return nil
        }
        return rect
    }

    func readClipboardDirectly() -> SelectionResult? {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string) else {
            Logger.info("SelectedTextExtractor: Clipboard contains no text")
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.info("SelectedTextExtractor: Clipboard text is empty")
            return nil
        }
        Logger.info("SelectedTextExtractor: Direct clipboard read='\(trimmed)' (no bounds)")
        return SelectionResult(text: trimmed, bounds: nil)
    }

    // MARK: - Clipboard fallback (universal, works in VSCode/Cursor/Sublime/web)

    private func readViaClipboard() -> SelectionResult? {
        let pb = NSPasteboard.general
        let oldChangeCount = pb.changeCount
        let savedItems = snapshotPasteboard(pb)
        Logger.info("SelectedTextExtractor: clipboard pre-changeCount=\(oldChangeCount)")

        // The user is holding the hotkey. We synthesize a Cmd+C key event with
        // its own flags (.maskCommand only), which overrides the physical
        // modifier state for that one event — so the target app sees a clean
        // Cmd+C, not Cmd+Shift+C.
        guard sendCmdC() else {
            Logger.info("SelectedTextExtractor: Failed to synthesize Cmd+C")
            restorePasteboard(pb, items: savedItems)
            return nil
        }

        // Poll until the target app updates the pasteboard, with a hard cap.
        var copied: String?
        let deadline = Date().addingTimeInterval(0.25)
        while Date() < deadline {
            if pb.changeCount != oldChangeCount {
                copied = pb.string(forType: .string)
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        let postChangeCount = pb.changeCount
        restorePasteboard(pb, items: savedItems)

        guard let text = copied else {
            Logger.info("SelectedTextExtractor: Clipboard unchanged after Cmd+C (pre=\(oldChangeCount), post=\(postChangeCount)). Likely no selection or app didn't honour Cmd+C.")
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.info("SelectedTextExtractor: Clipboard text empty")
            return nil
        }
        Logger.info("SelectedTextExtractor: Clipboard selected='\(trimmed)' (no bounds)")
        return SelectionResult(text: trimmed, bounds: nil)
    }

    private func sendCmdC() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 0x08  // kVK_ANSI_C
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func snapshotPasteboard(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        var snapshot: [NSPasteboardItem] = []
        for item in pb.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            snapshot.append(copy)
        }
        return snapshot
    }

    private func restorePasteboard(_ pb: NSPasteboard, items: [NSPasteboardItem]) {
        pb.clearContents()
        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }
}
