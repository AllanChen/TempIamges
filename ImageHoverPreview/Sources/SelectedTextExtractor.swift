import AppKit
import ApplicationServices
import CoreGraphics

class SelectedTextExtractor {
    func extractSelectedText() -> String? {
        if let text = readViaAX() {
            return text
        }
        Logger.info("SelectedTextExtractor: AX yielded nothing, trying clipboard")
        return readViaClipboard()
    }

    // MARK: - AX path (native Cocoa apps)

    private func readViaAX() -> String? {
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
        Logger.info("SelectedTextExtractor: AX selected='\(trimmed)'")
        return trimmed
    }

    // MARK: - Clipboard fallback (universal, works in VSCode/Cursor/Sublime/web)

    private func readViaClipboard() -> String? {
        let pb = NSPasteboard.general
        let oldChangeCount = pb.changeCount
        let savedItems = snapshotPasteboard(pb)

        // The user is holding Cmd+Shift. We synthesize a Cmd+C key event with
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

        restorePasteboard(pb, items: savedItems)

        guard let text = copied else {
            Logger.info("SelectedTextExtractor: Clipboard unchanged after Cmd+C (no selection?)")
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.info("SelectedTextExtractor: Clipboard text empty")
            return nil
        }
        Logger.info("SelectedTextExtractor: Clipboard selected='\(trimmed)'")
        return trimmed
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
