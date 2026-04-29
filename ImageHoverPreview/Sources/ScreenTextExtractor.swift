import AppKit
import CoreGraphics
import Vision

class ScreenTextExtractor {
    private let ocrRequest: VNRecognizeTextRequest

    // Wider + taller region: catches long URLs in dev tools and gives us
    // multiple lines so we can stitch a wrapped URL or pick the candidate
    // physically closest to the cursor.
    private let regionWidth: CGFloat = 1100
    private let regionHeight: CGFloat = 160

    init() {
        ocrRequest = VNRecognizeTextRequest()
        ocrRequest.recognitionLevel = .accurate
        // URLs and paths aren't natural language — language correction turns
        // "https" into "htps" and similar, breaking detection.
        ocrRequest.usesLanguageCorrection = false
    }

    // Backwards-compatible joined output. Lines are joined with newline so
    // PathDetector.unwrapLines can stitch a soft-wrapped URL.
    func extractText(at screenPoint: CGPoint) -> String? {
        guard let observations = recognize(at: screenPoint) else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    // Find the URL/path candidate whose bounding box is closest to the cursor.
    // The cursor is at the centre of the captured region, i.e. normalized
    // (0.5, 0.5) in Vision's bounding-box space. This disambiguates when
    // multiple candidates are visible (typical for code editors).
    func extractNearestPathOrURL(at screenPoint: CGPoint, using detector: PathDetector) -> String? {
        guard let observations = recognize(at: screenPoint) else {
            Logger.info("ScreenTextExtractor: No OCR observations for nearest-candidate search")
            return nil
        }

        Logger.info("ScreenTextExtractor: Scanning \(observations.count) OCR lines for nearest path/URL")

        let sorted = observations.sorted { a, b in
            if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.05 {
                return a.boundingBox.midY > b.boundingBox.midY
            }
            return a.boundingBox.midX < b.boundingBox.midX
        }

        // Pass 1: per-line candidate, pick the one closest to cursor.
        var perLine: [(text: String, distance: CGFloat, line: String)] = []
        for obs in sorted {
            guard let line = obs.topCandidates(1).first?.string else { continue }
            if let candidate = detector.firstImageCandidate(in: line) {
                let dx = obs.boundingBox.midX - 0.5
                let dy = obs.boundingBox.midY - 0.5
                let dist = sqrt(dx * dx + dy * dy)
                perLine.append((candidate, dist, line))
            }
        }
        if let best = perLine.min(by: { $0.distance < $1.distance }) {
            Logger.info("ScreenTextExtractor: Nearest per-line candidate='\(best.text)' distance=\(String(format: "%.3f", best.distance)) line='\(best.line)'")
            return best.text
        }

        // Pass 2: stitch adjacent lines (soft-wrapped URLs).
        let combined = sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        if let candidate = detector.firstImageCandidate(in: combined) {
            Logger.info("ScreenTextExtractor: Stitched-line candidate='\(candidate)'")
            return candidate
        }

        // Pass 3: collapse all whitespace and rescan — last-ditch attempt for
        // URLs split across glyph runs by the OCR engine.
        let unwrapped = combined.components(separatedBy: .whitespacesAndNewlines).joined()
        if let candidate = detector.firstImageCandidate(in: unwrapped) {
            Logger.info("ScreenTextExtractor: Fully-unwrapped candidate='\(candidate)'")
            return candidate
        }

        Logger.info("ScreenTextExtractor: No image path/URL found near cursor")
        return nil
    }

    private func recognize(at screenPoint: CGPoint) -> [VNRecognizedTextObservation]? {
        Logger.info("ScreenTextExtractor: Starting OCR at point (\(screenPoint.x), \(screenPoint.y))")

        guard let cgImage = captureCGImage(around: screenPoint) else {
            Logger.info("ScreenTextExtractor: Failed to capture screen region")
            return nil
        }

        Logger.info("ScreenTextExtractor: CGImage created, size=(\(cgImage.width), \(cgImage.height))")

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([ocrRequest])
        } catch {
            Logger.info("ScreenTextExtractor: Vision request failed: \(error)")
            return nil
        }

        return ocrRequest.results
    }

    private func captureCGImage(around point: CGPoint) -> CGImage? {
        guard let (displayID, displayFrame) = displayContainingWithFrame(point: point) else {
            Logger.info("ScreenTextExtractor: Could not find display for point (\(point.x), \(point.y))")
            return nil
        }

        // `point` arrives in AX/CG coords (y-down from the top of the screen
        // the cursor is on). NSScreen.frame is NS coords (y-up from primary
        // bottom). Both share the same x-axis, so we only need to use the
        // x-origin to convert to display-local pixels for the capture call.
        let localX = point.x - displayFrame.origin.x
        let localY = point.y  // already display-local in y for the origin display

        let rect = CGRect(
            x: localX - regionWidth / 2,
            y: localY - regionHeight / 2,
            width: regionWidth,
            height: regionHeight
        )

        let bounded = rect.intersection(CGRect(origin: .zero, size: displayFrame.size))
        guard !bounded.isEmpty else {
            Logger.info("ScreenTextExtractor: Capture rect outside display bounds")
            return nil
        }

        Logger.info("ScreenTextExtractor: Capturing rect \(bounded) on display \(displayID)")
        return CGDisplayCreateImageForRect(displayID, bounded)
    }

    private func displayContainingWithFrame(point: CGPoint) -> (CGDirectDisplayID, CGRect)? {
        let screens = NSScreen.screens
        for screen in screens {
            let frame = screen.frame
            if NSMouseInRect(point, frame, false) {
                let key = NSDeviceDescriptionKey("NSScreenNumber")
                if let n = screen.deviceDescription[key] as? NSNumber {
                    return (CGDirectDisplayID(n.uint32Value), frame)
                }
            }
        }
        if let main = screens.first {
            return (CGMainDisplayID(), main.frame)
        }
        return nil
    }
}

@_silgen_name("CGDisplayCreateImageForRect")
private func CGDisplayCreateImageForRect(_ display: CGDirectDisplayID, _ rect: CGRect) -> CGImage?
