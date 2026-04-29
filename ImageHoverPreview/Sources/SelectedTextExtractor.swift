import AppKit
import ApplicationServices

class SelectedTextExtractor {
    func extractSelectedText() -> String? {
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
            Logger.info("SelectedTextExtractor: Selected text is empty")
            return nil
        }
        Logger.info("SelectedTextExtractor: selected='\(trimmed)'")
        return trimmed
    }
}
