import AppKit
import ApplicationServices

class TextExtractor {
    private var lastExtractedText: String?
    private var lastExtractionTime: Date?
    private let debounceInterval: TimeInterval = 0.1
    private let screenTextExtractor = ScreenTextExtractor()

    func extractText(at point: CGPoint, debounce: Bool = true) -> String? {
        if debounce {
            if let lastTime = lastExtractionTime,
               Date().timeIntervalSince(lastTime) < debounceInterval {
                return lastExtractedText
            }
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)

        guard result == .success, let el = element else {
            print("TextExtractor: No element at position (\(point.x), \(point.y)), trying OCR fallback")
            return screenTextExtractor.extractText(at: point)
        }

        // Walk up to 5 ancestors looking for the most useful text/URL.
        // Browsers often present the URL on a parent <a> / <img> element while the
        // child element under the cursor has only the visible text or no value at all.
        var current: AXUIElement? = el
        var collected: [String] = []
        var depth = 0

        while let node = current, depth < 5 {
            if let url = readURL(from: node) {
                collected.append(url)
                break
            }
            if let s = readString(node, kAXSelectedTextAttribute), !s.isEmpty {
                collected.append(s)
            }
            if let s = readString(node, kAXValueAttribute), !s.isEmpty {
                collected.append(s)
            }
            if let s = readString(node, kAXDescriptionAttribute), !s.isEmpty {
                collected.append(s)
            }
            if let s = readString(node, kAXTitleAttribute), !s.isEmpty {
                collected.append(s)
            }
            if let s = readString(node, kAXHelpAttribute), !s.isEmpty {
                collected.append(s)
            }

            // Stop early once we already have a candidate that looks like a URL or path.
            if collected.contains(where: looksLikePathOrURL) {
                break
            }

            current = parent(of: node)
            depth += 1
        }

        let text = collected.first(where: looksLikePathOrURL) ?? collected.first

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("TextExtractor: latency=\(String(format: "%.2f", elapsed))ms text='\(text ?? "nil")' position=(\(point.x), \(point.y))")

        if text != nil {
            lastExtractedText = text
            lastExtractionTime = Date()
        }

        return text
    }

    func reset() {
        lastExtractedText = nil
        lastExtractionTime = nil
    }

    // MARK: - Helpers

    private func readString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let val = value else {
            return nil
        }
        if CFGetTypeID(val) == CFStringGetTypeID() {
            return (val as! CFString) as String
        }
        return nil
    }

    private func readURL(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
              let val = value else {
            return nil
        }
        if CFGetTypeID(val) == CFURLGetTypeID() {
            let url = val as! CFURL
            return (url as URL).absoluteString
        }
        if CFGetTypeID(val) == CFStringGetTypeID() {
            return (val as! CFString) as String
        }
        return nil
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let val = value,
              CFGetTypeID(val) == AXUIElementGetTypeID() else {
            return nil
        }
        return (val as! AXUIElement)
    }

    private func looksLikePathOrURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("http://") || t.contains("https://") || t.contains("file://") {
            return true
        }
        if t.contains("/") && (t.contains(".jpg") || t.contains(".jpeg") || t.contains(".png")
            || t.contains(".gif") || t.contains(".webp") || t.contains(".heic")
            || t.contains(".heif") || t.contains(".bmp") || t.contains(".tiff") || t.contains(".tif")) {
            return true
        }
        return false
    }
}
