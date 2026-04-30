import Foundation

enum DetectedPath {
    case localImage(URL)
    case remoteImage(URL)
    case invalid

    var url: URL? {
        switch self {
        case .localImage(let url), .remoteImage(let url):
            return url
        case .invalid:
            return nil
        }
    }

    var isImage: Bool {
        switch self {
        case .localImage, .remoteImage:
            return true
        case .invalid:
            return false
        }
    }
}

class PathDetector {
    private let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"
    ]

    private let httpRegex: NSRegularExpression
    private let fileURLRegex: NSRegularExpression
    private let absolutePathRegex: NSRegularExpression
    private let homePathRegex: NSRegularExpression
    private let allRegexes: [NSRegularExpression]

    init() {
        let exts = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"]
        let extAlt = exts.joined(separator: "|")

        self.httpRegex = try! NSRegularExpression(
            pattern: "https?://[^\\s\"'<>()\\[\\]{}]+?\\.(?i:\(extAlt))(?:\\?[^\\s\"'<>]*)?",
            options: []
        )
        self.fileURLRegex = try! NSRegularExpression(
            pattern: "file://[^\\s\"'<>()\\[\\]{}]+?\\.(?i:\(extAlt))",
            options: []
        )
        self.absolutePathRegex = try! NSRegularExpression(
            pattern: "/[^\\s\"'<>()\\[\\]{}]+?\\.(?i:\(extAlt))",
            options: []
        )
        self.homePathRegex = try! NSRegularExpression(
            pattern: "~/[^\\s\"'<>()\\[\\]{}]+?\\.(?i:\(extAlt))",
            options: []
        )

        self.allRegexes = [httpRegex, fileURLRegex, homePathRegex, absolutePathRegex]
    }

    func detect(_ text: String) -> DetectedPath {
        return detectAll(text).first ?? .invalid
    }

    func detectAll(_ text: String) -> [DetectedPath] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        Logger.info("PathDetector: scanning text='\(truncate(trimmed))'")

        var results = collectAll(in: trimmed)
        if results.isEmpty {
            // Editors with soft-wrap and multi-line OCR output frequently
            // break a long URL/path in the middle. Retry with line breaks and
            // surrounding spaces removed.
            let unwrapped = unwrapLines(trimmed)
            if unwrapped != trimmed {
                Logger.info("PathDetector: retrying unwrapped='\(truncate(unwrapped))'")
                results = collectAll(in: unwrapped)
            }
        }

        Logger.info("PathDetector: detected \(results.count) image candidate(s)")
        return results
    }

    private func collectAll(in text: String) -> [DetectedPath] {
        struct Hit { let range: NSRange; let str: String; let priority: Int }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Lower priority number wins when ranges overlap (e.g. an http URL
        // contains an absolute-path-looking substring after the scheme).
        let prioritized: [(NSRegularExpression, Int)] = [
            (httpRegex, 0),
            (fileURLRegex, 1),
            (homePathRegex, 2),
            (absolutePathRegex, 3),
        ]

        var hits: [Hit] = []
        for (regex, prio) in prioritized {
            regex.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
                guard let m = m else { return }
                hits.append(Hit(range: m.range, str: ns.substring(with: m.range), priority: prio))
            }
        }

        hits.sort {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            if $0.priority != $1.priority {
                return $0.priority < $1.priority
            }
            return $0.range.length > $1.range.length
        }

        var results: [DetectedPath] = []
        var seen = Set<String>()
        var lastEnd = 0
        for hit in hits {
            if hit.range.location < lastEnd { continue }
            lastEnd = hit.range.location + hit.range.length
            guard let path = resolveCandidate(hit.str), let url = path.url else { continue }
            let key = url.absoluteString
            if seen.insert(key).inserted {
                Logger.info("PathDetector: matched '\(hit.str)' -> '\(key)'")
                results.append(path)
            }
        }
        return results
    }

    private func resolveCandidate(_ candidate: String) -> DetectedPath? {
        let lower = candidate.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: candidate).map { .remoteImage($0) }
        }
        if lower.hasPrefix("file://") {
            if let url = URL(string: candidate), isValidLocalImage(path: url.path) {
                return .localImage(URL(fileURLWithPath: url.path))
            }
            return nil
        }
        if candidate.hasPrefix("~/") {
            let expanded = (candidate as NSString).expandingTildeInPath
            if isValidLocalImage(path: expanded) {
                return .localImage(URL(fileURLWithPath: expanded))
            }
            return nil
        }
        if candidate.hasPrefix("/") {
            if isValidLocalImage(path: candidate) {
                return .localImage(URL(fileURLWithPath: candidate))
            }
            return nil
        }
        return nil
    }

    private func unwrapLines(_ text: String) -> String {
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined()
    }

    private func isValidLocalImage(path: String) -> Bool {
        if path.contains("..") {
            return false
        }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            Logger.info("PathDetector: file does not exist at '\(path)'")
            return false
        }
        guard !isDirectory.boolValue else {
            return false
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    private func truncate(_ s: String, max: Int = 200) -> String {
        if s.count <= max { return s }
        let prefix = s.prefix(max)
        return "\(prefix)…(\(s.count - max) more chars)"
    }
}
