import AppKit
import ApplicationServices

class TextExtractor {
    private var lastExtractedText: String?
    private var lastExtractionTime: Date?
    private let debounceInterval: TimeInterval = 0.1
    private let screenTextExtractor = ScreenTextExtractor()
    private let pathDetector = PathDetector()

    func extractText(at point: CGPoint, debounce: Bool = true) -> String? {
        if debounce {
            if let lastTime = lastExtractionTime,
               Date().timeIntervalSince(lastTime) < debounceInterval {
                return lastExtractedText
            }
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let axText = extractFromAX(at: point)

        // 1) AX returned exactly one image-path/URL candidate — unambiguous,
        //    trust AX. This is the Notes / Safari / native-app fast path.
        if let t = axText {
            let count = pathDetector.countImageCandidates(in: t)
            if count == 1 {
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                Logger.info("TextExtractor: latency=\(String(format: "%.2f", elapsed))ms source=AX-unique text='\(truncate(t))'")
                cache(t)
                return t
            }
            Logger.info("TextExtractor: AX text has \(count) candidates, length=\(t.count) — using OCR for disambiguation")
        }

        // 2) AX is ambiguous (multiple URLs in a line of code) or empty.
        //    Use OCR with bounding-box scoring to pick the candidate
        //    physically closest to the cursor. This is the dev-tools path.
        if let nearest = screenTextExtractor.extractNearestPathOrURL(at: point, using: pathDetector) {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            Logger.info("TextExtractor: latency=\(String(format: "%.2f", elapsed))ms source=OCR-nearest text='\(nearest)'")
            cache(nearest)
            return nearest
        }

        // 3) OCR found nothing. If AX gave us *any* text, try the legacy OCR
        //    pass (joined lines) so PathDetector's unwrap step has a chance
        //    on heavily-wrapped text. Otherwise return AX text as-is so the
        //    caller can show "No image found".
        if let ocr = screenTextExtractor.extractText(at: point), !ocr.isEmpty {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            Logger.info("TextExtractor: latency=\(String(format: "%.2f", elapsed))ms source=OCR-fallback text='\(truncate(ocr))'")
            cache(ocr)
            return ocr
        }

        if let t = axText {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            Logger.info("TextExtractor: latency=\(String(format: "%.2f", elapsed))ms source=AX-raw text='\(truncate(t))'")
            cache(t)
            return t
        }

        return nil
    }

    private func cache(_ text: String) {
        lastExtractedText = text
        lastExtractionTime = Date()
    }

    private func extractFromAX(at point: CGPoint) -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)

        guard result == .success, let el = element else {
            Logger.info("TextExtractor: No AX element at position (\(point.x), \(point.y))")
            return nil
        }

        // Walk up to 5 ancestors looking for the most useful text/URL.
        // Browsers often present the URL on a parent <a> / <img> element while
        // the child element under the cursor has only the visible text or no
        // value at all.
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

            // Stop once we already have a candidate that looks like a URL or
            // path so we don't keep climbing into a parent whose value is the
            // entire window.
            if collected.contains(where: looksLikePathOrURL) {
                break
            }

            current = parent(of: node)
            depth += 1
        }

        return collected.first(where: looksLikePathOrURL) ?? collected.first
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
        let lower = t.lowercased()
        if t.contains("/") && (lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png")
            || lower.contains(".gif") || lower.contains(".webp") || lower.contains(".heic")
            || lower.contains(".heif") || lower.contains(".bmp") || lower.contains(".tiff") || lower.contains(".tif")) {
            return true
        }
        return false
    }

    private func truncate(_ s: String, max: Int = 200) -> String {
        if s.count <= max { return s }
        let prefix = s.prefix(max)
        return "\(prefix)…(\(s.count - max) more chars)"
    }
}
