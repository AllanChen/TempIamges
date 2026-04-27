import AppKit
import CoreGraphics
import Vision

class ScreenTextExtractor {
    private let ocrRequest: VNRecognizeTextRequest

    init() {
        ocrRequest = VNRecognizeTextRequest()
        ocrRequest.recognitionLevel = .accurate
        ocrRequest.usesLanguageCorrection = true
    }

    func extractText(at screenPoint: CGPoint) -> String? {
        guard let screenshot = captureRegion(around: screenPoint) else {
            print("ScreenTextExtractor: Failed to capture screen region")
            return nil
        }

        guard let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("ScreenTextExtractor: Failed to get CGImage")
            return nil
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([ocrRequest])
        } catch {
            print("ScreenTextExtractor: Vision request failed: \(error)")
            return nil
        }

        guard let results = ocrRequest.results else {
            print("ScreenTextExtractor: No OCR results")
            return nil
        }

        // Vision returns observations roughly in reading order, but for
        // robustness sort top-to-bottom (boundingBox origin is bottom-left
        // in normalized coords, so a larger y is visually higher) and
        // then left-to-right. That way PathDetector's unwrap pass stitches
        // the lines back in the order a human would read them.
        let sorted = results.sorted { a, b in
            if abs(a.boundingBox.origin.y - b.boundingBox.origin.y) > 0.02 {
                return a.boundingBox.origin.y > b.boundingBox.origin.y
            }
            return a.boundingBox.origin.x < b.boundingBox.origin.x
        }

        let lines = sorted.compactMap { observation in
            observation.topCandidates(1).first?.string
        }

        let text = lines.joined(separator: "\n")
        print("ScreenTextExtractor: OCR result='\(text)'")

        return text.isEmpty ? nil : text
    }

    private func captureRegion(around point: CGPoint) -> NSImage? {
        // Wider region than the cursor cell so that long URLs/paths typed
        // out in code editors are captured even when the cursor is near
        // the start or end of the token.
        let regionWidth: CGFloat = 1000
        let regionHeight: CGFloat = 180

        let rect = CGRect(
            x: point.x - regionWidth / 2,
            y: point.y - regionHeight / 2,
            width: regionWidth,
            height: regionHeight
        )

        guard let displayID = displayContaining(point: point) else {
            print("ScreenTextExtractor: Could not find display for point (\(point.x), \(point.y))")
            return nil
        }

        guard let imageRef = CGDisplayCreateImageForRect(displayID, rect) else {
            print("ScreenTextExtractor: CGDisplayCreateImageForRect failed")
            return nil
        }

        let image = NSImage(cgImage: imageRef, size: NSSize(width: rect.width, height: rect.height))
        return image
    }

    private func displayContaining(point: CGPoint) -> CGDirectDisplayID? {
        var matchingDisplay: CGDirectDisplayID?

        let screens = NSScreen.screens
        for screen in screens {
            let frame = screen.frame
            if NSMouseInRect(point, frame, false) {
                let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
                if let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber {
                    matchingDisplay = CGDirectDisplayID(screenNumber.uint32Value)
                    break
                }
            }
        }

        return matchingDisplay ?? CGMainDisplayID()
    }
}

@_silgen_name("CGDisplayCreateImageForRect")
private func CGDisplayCreateImageForRect(_ display: CGDirectDisplayID, _ rect: CGRect) -> CGImage?
