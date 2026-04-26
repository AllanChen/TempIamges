import AppKit
import ApplicationServices

class TextExtractor {
    private var lastExtractedText: String?
    private var lastExtractionTime: Date?
    private let debounceInterval: TimeInterval = 0.1

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
            print("TextExtractor: No element at position (\(point.x), \(point.y))")
            return nil
        }

        var text: String? = nil
        var value: CFTypeRef?

        if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value) == .success,
           let val = value,
           CFGetTypeID(val) == CFStringGetTypeID() {
            let str = (val as! CFString) as String
            if !str.isEmpty {
                text = str
            }
        }

        if text == nil {
            if AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &value) == .success,
               let val = value,
               CFGetTypeID(val) == CFStringGetTypeID() {
                let str = (val as! CFString) as String
                if !str.isEmpty {
                    text = str
                }
            }
        }

        if text == nil {
            if AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &value) == .success,
               let val = value,
               CFGetTypeID(val) == CFStringGetTypeID() {
                let str = (val as! CFString) as String
                if !str.isEmpty {
                    text = str
                }
            }
        }

        if text == nil {
            var focusedElement: AXUIElement?
            if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
               let focused = value,
               CFGetTypeID(focused) == AXUIElementGetTypeID() {
                focusedElement = (focused as! AXUIElement)
                if AXUIElementCopyAttributeValue(focusedElement!, kAXValueAttribute as CFString, &value) == .success,
                   let val = value,
                   CFGetTypeID(val) == CFStringGetTypeID() {
                    let str = (val as! CFString) as String
                    if !str.isEmpty {
                        text = str
                    }
                }
            }
        }

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
}
