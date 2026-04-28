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
        Logger.info("ScreenTextExtractor: Starting OCR at point (\(screenPoint.x), \(screenPoint.y))")
        
        guard let screenshot = captureRegion(around: screenPoint) else {
            Logger.info("ScreenTextExtractor: Failed to capture screen region")
            return nil
        }
        
        Logger.info("ScreenTextExtractor: Screenshot captured successfully, size=(\(screenshot.size.width), \(screenshot.size.height))")

        guard let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Logger.info("ScreenTextExtractor: Failed to get CGImage")
            return nil
        }
        
        Logger.info("ScreenTextExtractor: CGImage created, size=(\(cgImage.width), \(cgImage.height))")

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([ocrRequest])
            Logger.info("ScreenTextExtractor: Vision request performed successfully")
        } catch {
            Logger.info("ScreenTextExtractor: Vision request failed: \(error)")
            return nil
        }

        guard let results = ocrRequest.results else {
            Logger.info("ScreenTextExtractor: No OCR results")
            return nil
        }
        
        Logger.info("ScreenTextExtractor: Found \(results.count) text observations")

        // Vision returns observations roughly in reading order, but for
        // robustness sort top-to-bottom (boundingBox origin is bottom-left
        // in normalized coords, so a larger y is visually higher) and
        // then left-to-right. That way PathDetector's unwrap pass stitches
        // the lines back in the order a human would read them.
        let lines = results.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        
        Logger.info("ScreenTextExtractor: Extracted \(lines.count) lines: \(lines)")

        let text = lines.joined(separator: " ")
        Logger.info("ScreenTextExtractor: OCR final result='\(text)'")

        return text.isEmpty ? nil : text
    }

    private func captureRegion(around point: CGPoint) -> NSImage? {
        let regionWidth: CGFloat = 800
        let regionHeight: CGFloat = 60

        guard let (displayID, displayFrame) = displayContainingWithFrame(point: point) else {
            Logger.info("ScreenTextExtractor: Could not find display for point (\(point.x), \(point.y))")
            return nil
        }

        let localPoint = CGPoint(
            x: point.x - displayFrame.origin.x,
            y: point.y - displayFrame.origin.y
        )

        let rect = CGRect(
            x: localPoint.x - regionWidth / 2,
            y: localPoint.y - regionHeight / 2,
            width: regionWidth,
            height: regionHeight
        )

        let boundedRect = rect.intersection(CGRect(origin: .zero, size: displayFrame.size))
        
        guard !boundedRect.isEmpty else {
            Logger.info("ScreenTextExtractor: Rect is outside display bounds")
            return nil
        }

        Logger.info("ScreenTextExtractor: Capturing rect \(boundedRect) on display \(displayID)")

        guard let imageRef = CGDisplayCreateImageForRect(displayID, boundedRect) else {
            Logger.info("ScreenTextExtractor: CGDisplayCreateImageForRect failed")
            return nil
        }

        let image = NSImage(cgImage: imageRef, size: NSSize(width: boundedRect.width, height: boundedRect.height))
        return image
    }

    private func displayContainingWithFrame(point: CGPoint) -> (CGDirectDisplayID, CGRect)? {
        let screens = NSScreen.screens
        for screen in screens {
            let frame = screen.frame
            if NSMouseInRect(point, frame, false) {
                let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
                if let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber {
                    let displayID = CGDirectDisplayID(screenNumber.uint32Value)
                    return (displayID, frame)
                }
            }
        }
        
        let mainDisplay = CGMainDisplayID()
        if let mainScreen = screens.first {
            return (mainDisplay, mainScreen.frame)
        }
        
        return nil
    }
}

@_silgen_name("CGDisplayCreateImageForRect")
private func CGDisplayCreateImageForRect(_ display: CGDirectDisplayID, _ rect: CGRect) -> CGImage?
