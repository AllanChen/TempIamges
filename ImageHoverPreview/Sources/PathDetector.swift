import Foundation

enum DetectedPath {
    case localImage(URL)
    case remoteImage(URL)
    case localVideo(URL)
    case remoteVideo(URL)
    case localMarkdown(URL)
    case remoteMarkdown(URL)
    case webPage(URL)
    /// Bare filename in the selection (no slashes), e.g. "screenshot.png".
    /// FileNameResolver will Spotlight-search for this before previewing.
    case unresolvedFilename(String)
    /// Relative path with at least one slash, e.g. "./assets/foo.png" or
    /// "src/img/a.jpg".
    case unresolvedRelativePath(String)
    case invalid

    var url: URL? {
        switch self {
        case .localImage(let url), .remoteImage(let url),
             .localVideo(let url), .remoteVideo(let url),
             .localMarkdown(let url), .remoteMarkdown(let url),
             .webPage(let url):
            return url
        case .unresolvedFilename, .unresolvedRelativePath, .invalid:
            return nil
        }
    }

    var isVideo: Bool {
        switch self {
        case .localVideo, .remoteVideo: return true
        default: return false
        }
    }

    var isMedia: Bool {
        switch self {
        case .localImage, .remoteImage,
             .localVideo, .remoteVideo,
             .localMarkdown, .remoteMarkdown,
             .webPage:
            return true
        case .unresolvedFilename, .unresolvedRelativePath, .invalid:
            return false
        }
    }

    var isUnresolved: Bool {
        switch self {
        case .unresolvedFilename, .unresolvedRelativePath: return true
        default: return false
        }
    }

    /// Raw token for unresolved cases — handed to FileNameResolver. `nil` for
    /// concrete cases.
    var unresolvedToken: String? {
        switch self {
        case .unresolvedFilename(let s), .unresolvedRelativePath(let s): return s
        default: return nil
        }
    }
}

class PathDetector {
    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"
    ]
    private let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "webm"
    ]
    private let markdownExtensions: Set<String> = ["md", "markdown"]
    private var localSupportedExtensions: Set<String> {
        imageExtensions.union(videoExtensions).union(markdownExtensions)
    }

    private let httpRegex: NSRegularExpression
    private let fileURLRegex: NSRegularExpression
    private let absolutePathRegex: NSRegularExpression
    private let homePathRegex: NSRegularExpression
    private let relativePathRegex: NSRegularExpression
    private let bareFilenameRegex: NSRegularExpression
    private let allRegexes: [NSRegularExpression]

    init() {
        // Local file regex matches only paths with supported extensions so we
        // don't surface arbitrary file paths as previewable.
        let localExts = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif",
                         "bmp", "tiff", "tif",
                         "mp4", "mov", "m4v", "webm",
                         "md", "markdown"]
        let extAlt = localExts.joined(separator: "|")

        // Remote http(s) URLs are detected extension-agnostically; the kind is
        // decided in resolveCandidate() based on the URL's extension. Anything
        // without a recognised media extension falls into .webPage.
        self.httpRegex = try! NSRegularExpression(
            pattern: "https?://[^\\s\"'<>()\\[\\]{}]+",
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
        // Relative path: at least one interior '/', optional ./ or ../ prefix.
        // Lookbehind avoids overlap with absolute/home/file:// regexes.
        self.relativePathRegex = try! NSRegularExpression(
            pattern: "(?<![A-Za-z0-9_/~])(?:\\./|\\.\\./)*[A-Za-z0-9_.\\-]+/[A-Za-z0-9_./\\-]+?\\.(?i:\(extAlt))(?![A-Za-z0-9])",
            options: []
        )
        // Bare filename: stem ≥3 chars, alphanumeric/_/-/., must be standalone
        // (not preceded by slashes, tildes, dots, dashes, or alphanumerics).
        self.bareFilenameRegex = try! NSRegularExpression(
            pattern: "(?<![A-Za-z0-9_./~\\-])[A-Za-z0-9_][A-Za-z0-9_.\\-]{2,}\\.(?i:\(extAlt))(?![A-Za-z0-9])",
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

        // ─── Phase A: existing absolute-path / URL detectors. ─────────────
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

        // ─── Phase B: relative-path regex (always runs, additive). ────────
        relativePathRegex.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m = m else { return }
            hits.append(Hit(range: m.range, str: ns.substring(with: m.range), priority: 4))
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
            guard let path = resolveCandidate(hit.str) else { continue }
            // Dedup: concrete cases use URL string; unresolved cases use token.
            let key = path.url?.absoluteString ?? path.unresolvedToken ?? ""
            if key.isEmpty { continue }
            if seen.insert(key).inserted {
                Logger.info("PathDetector: matched '\(hit.str)' -> '\(key)'")
                results.append(path)
            }
        }

        // ─── Phase C: bare-filename regex. ─────────────────────────────────
        // Runs whenever Phase A+B produced no concrete URLs. The regex is
        // already strict (stem ≥3 chars + alphanumeric/_/-, must end in a
        // supported media extension), so prose false positives are rare. To
        // bound Spotlight load on huge selections, cap to N candidates per
        // call.
        let maxBareCandidates = 16
        let phaseAOrBHadConcreteURL = results.contains { $0.url != nil }
        if !phaseAOrBHadConcreteURL && text.count <= 5000 {
            var bareCount = 0
            bareFilenameRegex.enumerateMatches(in: text, options: [], range: full) { m, _, stop in
                guard let m = m else { return }
                let token = ns.substring(with: m.range)
                if seen.insert(token).inserted {
                    Logger.info("PathDetector: bare filename candidate '\(token)'")
                    results.append(.unresolvedFilename(token))
                    bareCount += 1
                    if bareCount >= maxBareCandidates {
                        stop.pointee = true
                    }
                }
            }
        }
        return results
    }

    private func resolveCandidate(_ candidate: String) -> DetectedPath? {
        let lower = candidate.lowercased()
        let ext = mediaExtension(of: candidate)
        let isImage = imageExtensions.contains(ext)
        let isVideo = videoExtensions.contains(ext)
        let isMarkdown = markdownExtensions.contains(ext)

        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = parseLenientURL(candidate) else { return nil }
            if isImage    { return .remoteImage(url) }
            if isVideo    { return .remoteVideo(url) }
            if isMarkdown { return .remoteMarkdown(url) }
            // Anything else with http(s) scheme is treated as a webpage URL.
            return .webPage(url)
        }
        if lower.hasPrefix("file://") {
            if let url = parseLenientURL(candidate), isValidLocalMedia(path: url.path) {
                return localKind(for: url.path)
            }
            return nil
        }
        if candidate.hasPrefix("~/") {
            let expanded = (candidate as NSString).expandingTildeInPath
            if isValidLocalMedia(path: expanded) {
                return localKind(for: expanded)
            }
            return nil
        }
        if candidate.hasPrefix("/") {
            if isValidLocalMedia(path: candidate) {
                return localKind(for: candidate)
            }
            return nil
        }
        // Anything else captured by collectAll's regex pipeline (specifically
        // the relativePathRegex) is treated as an unresolved relative path —
        // the resolver will Spotlight it.
        if candidate.contains("/") {
            return .unresolvedRelativePath(candidate)
        }
        return nil
    }

    /// Parse a URL string, tolerating non-ASCII characters that `URL(string:)`
    /// would otherwise reject.
    ///
    /// Strategy:
    ///   1. Try the raw string.
    ///   2. On macOS 14+ retry with the lenient initializer that percent-encodes
    ///      invalid characters automatically.
    ///   3. Fall back to manual percent-encoding for older systems, keeping
    ///      URL-syntax characters (`:/?#&=%@` etc.) intact and only escaping
    ///      things like CJK / accented Latin in the path or query.
    private func parseLenientURL(_ s: String) -> URL? {
        if let url = URL(string: s) { return url }

        if #available(macOS 14.0, *) {
            if let url = URL(string: s, encodingInvalidCharacters: true) {
                return url
            }
        }

        // Percent-encode anything outside the union of URL-syntax allowed sets.
        // This lets characters like 图片 turn into %E5%9B%BE%E7%89%87 while
        // leaving `:/?#&=%` alone so the URL structure isn't mangled.
        let safe = CharacterSet.urlPathAllowed
            .union(.urlHostAllowed)
            .union(.urlQueryAllowed)
            .union(.urlFragmentAllowed)
            .union(CharacterSet(charactersIn: ":/?#&=%@"))
        if let encoded = s.addingPercentEncoding(withAllowedCharacters: safe),
           let url = URL(string: encoded) {
            return url
        }
        return nil
    }

    private func localKind(for path: String) -> DetectedPath {
        let ext = (path as NSString).pathExtension.lowercased()
        let url = URL(fileURLWithPath: path)
        if videoExtensions.contains(ext)    { return .localVideo(url) }
        if markdownExtensions.contains(ext) { return .localMarkdown(url) }
        return .localImage(url)
    }

    private func mediaExtension(of candidate: String) -> String {
        // Strip query string before pathExtension lookup, since the http
        // regex captures `?...` for remote URLs.
        let withoutQuery = candidate.split(separator: "?", maxSplits: 1).first.map(String.init) ?? candidate
        return (withoutQuery as NSString).pathExtension.lowercased()
    }

    private func unwrapLines(_ text: String) -> String {
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined()
    }

    private func isValidLocalMedia(path: String) -> Bool {
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
        return localSupportedExtensions.contains(ext)
    }

    private func truncate(_ s: String, max: Int = 200) -> String {
        if s.count <= max { return s }
        let prefix = s.prefix(max)
        return "\(prefix)…(\(s.count - max) more chars)"
    }
}
