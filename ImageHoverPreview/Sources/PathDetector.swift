import Foundation

enum DetectedPath {
    case localImage(URL)
    case remoteImage(URL)
    case localVideo(URL)
    case remoteVideo(URL)
    case localMarkdown(URL)
    case remoteMarkdown(URL)
    case localText(URL)
    case remoteText(URL)
    case localPDF(URL)
    case remotePDF(URL)
    case webPage(URL)
    /// "Other" file types — known files we can't preview inline (doc, psd,
    /// zip, mp3, …). They show as a generic icon tile and click reveals
    /// them in Finder (local) or opens the URL in the browser (remote).
    case localOther(URL)
    case remoteOther(URL)
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
             .localText(let url), .remoteText(let url),
             .localPDF(let url), .remotePDF(let url),
             .localOther(let url), .remoteOther(let url),
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
             .localText, .remoteText,
             .localPDF, .remotePDF,
             .localOther, .remoteOther,
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
        "mp4", "mov", "m4v", "webm", "mkv", "avi"
    ]
    private let markdownExtensions: Set<String> = ["md", "markdown"]
    /// Plain-text-ish formats the viewer can render as text. Includes the
    /// original data trio (txt/json/xml), markup/style/config formats, and a
    /// broad set of source-code extensions. JSON and XML get pretty-printed
    /// in ContentViewerWindow; everything else is shown verbatim.
    private let textExtensions: Set<String> = [
        // Data / config
        "txt", "json", "xml", "yaml", "yml", "toml", "ini", "conf", "env",
        "properties", "cfg", "csv", "tsv", "sql", "log",
        // Markup / web
        "html", "htm", "css", "scss", "sass", "less", "styl", "svg",
        "tex", "rst", "adoc", "asciidoc", "org",
        // Programming languages
        "py", "js", "mjs", "cjs", "ts", "tsx", "jsx",
        "swift", "java", "kt", "m", "mm",
        "c", "cpp", "cc", "cxx", "h", "hpp",
        "rb", "go", "rs", "php", "cs", "vb", "scala", "lua", "pl", "r",
        "dart", "ex", "exs", "erl", "hs", "ml", "fs", "jl",
        "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd",
        "graphql", "gql", "proto", "vue", "svelte", "astro",
    ]
    /// PDF — previewable in WKWebView (macOS renders PDFs natively).
    private let pdfExtensions: Set<String> = ["pdf"]

    /// Known file types we can't preview inline. Detection makes them
    /// surface as a generic icon tile; the click action reveals them in
    /// Finder (or opens the URL in the browser for remote ones).
    private let otherExtensions: Set<String> = [
        // Documents (PDFs handled separately so they preview inline)
        "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "pages", "numbers", "key", "odt", "ods", "odp", "rtf",
        "epub", "mobi",
        // Design
        "psd", "ai", "sketch", "fig", "xd", "eps", "indd", "afdesign",
        // Audio
        "mp3", "m4a", "wav", "flac", "aac", "ogg", "opus", "aiff",
        // Archives / disk images
        "zip", "tar", "gz", "tgz", "bz2", "7z", "rar", "dmg", "iso",
        // Binaries / installers
        "exe", "app", "deb", "rpm", "pkg", "msi", "appimage",
        // Camera raw
        "raw", "dng", "cr2", "nef", "arw",
        // Fonts
        "ttf", "otf", "woff", "woff2",
    ]
    private var localSupportedExtensions: Set<String> {
        imageExtensions
            .union(videoExtensions)
            .union(markdownExtensions)
            .union(textExtensions)
            .union(pdfExtensions)
            .union(otherExtensions)
    }

    private let httpRegex: NSRegularExpression
    private let bareDomainRegex: NSRegularExpression
    private let fileURLRegex: NSRegularExpression
    private let absolutePathRegex: NSRegularExpression
    private let homePathRegex: NSRegularExpression
    private let relativePathRegex: NSRegularExpression
    private let bareFilenameRegex: NSRegularExpression
    private let allRegexes: [NSRegularExpression]

    init() {
        // Local file regex matches only paths with known extensions so we
        // don't surface arbitrary "/anything.x" tokens as files. The union
        // covers media + text/code + "other" (pdf/doc/psd/zip/…) so the same
        // regex flags every supported kind.
        // Sort descending by length so longer extensions match before any
        // shorter prefixes (e.g. "markdown" before "md").
        let localExts = Array(
            imageExtensions
                .union(videoExtensions)
                .union(markdownExtensions)
                .union(textExtensions)
                .union(pdfExtensions)
                .union(otherExtensions)
        ).sorted { $0.count > $1.count }
        let extAlt = localExts.joined(separator: "|")

        // Remote http(s) URLs are detected extension-agnostically; the kind is
        // decided in resolveCandidate() based on the URL's extension. Anything
        // without a recognised media extension falls into .webPage.
        // The `:?` makes the colon optional so typos like `https//foo.com` still match.
        self.httpRegex = try! NSRegularExpression(
            pattern: "https?:?//[^\\s\"'<>()\\[\\]{},]+",
            options: []
        )
        // Bare domain without scheme — `www.foo.com[/...]` or `something.com[/...]`.
        // Restricted to a www. prefix or a known multi-letter TLD to bound
        // false-positive risk against ordinary prose with periods.
        self.bareDomainRegex = try! NSRegularExpression(
            pattern: "(?<![A-Za-z0-9._/@-])(?:www\\.[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+|[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.(?:com|net|org|io|ai|app|dev|co|me|info|xyz|page|site|store|tech|gov|edu))(?:/[^\\s\"'<>()\\[\\]{},]*)?(?![A-Za-z0-9])",
            options: []
        )
        // Comma is excluded so comma-separated lists of paths (e.g.
        // "/a/x.png,/b/y.png") are split cleanly into separate matches.
        // Whitespace inside the character class is intentionally allowed
        // (no `\s` exclusion) so paths like "/Users/lily/Desktop/Project
        // Access Guide.pdf" still match. The lazy `+?` minimises greediness
        // and `isValidLocalMedia` filters any over-extended candidate via
        // file-existence check. Newlines and tabs remain excluded so
        // matches can't span lines.
        self.fileURLRegex = try! NSRegularExpression(
            pattern: "file://[^\"'<>()\\[\\]{},\\n\\r\\t]+?\\.(?i:\(extAlt))",
            options: []
        )
        self.absolutePathRegex = try! NSRegularExpression(
            pattern: "/[^\"'<>()\\[\\]{},\\n\\r\\t]+?\\.(?i:\(extAlt))",
            options: []
        )
        self.homePathRegex = try! NSRegularExpression(
            pattern: "~/[^\"'<>()\\[\\]{},\\n\\r\\t]+?\\.(?i:\(extAlt))",
            options: []
        )
        // Relative path: at least one interior '/', optional ./ or ../ prefix.
        // Lookbehind avoids overlap with absolute/home/file:// regexes.
        // The second segment (after the first slash) allows spaces and tabs
        // so paths like "Desktop/work/Project Access Guide.pdf" match. The
        // first segment stays strict — letting it eat spaces would devour
        // narrative text leading up to the slash.
        self.relativePathRegex = try! NSRegularExpression(
            pattern: "(?<![A-Za-z0-9_/~])(?:\\./|\\.\\./)*[A-Za-z0-9_.\\-]+/[A-Za-z0-9_./\\- \\t]+?\\.(?i:\(extAlt))(?![A-Za-z0-9])",
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
        // bareDomainRegex has the lowest priority so scheme-prefixed URLs
        // (httpRegex) win when both match the same range.
        let prioritized: [(NSRegularExpression, Int)] = [
            (httpRegex, 0),
            (fileURLRegex, 1),
            (homePathRegex, 2),
            (absolutePathRegex, 3),
            (bareDomainRegex, 5),
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
            // Only "consume" range when the candidate actually validates —
            // an over-extended absolute-path match that doesn't exist on
            // disk shouldn't block shorter strict matches that follow.
            guard let path = resolveCandidate(hit.str) else { continue }
            lastEnd = hit.range.location + hit.range.length
            // Dedup: concrete cases use URL string; unresolved cases use token.
            let key = path.url?.absoluteString ?? path.unresolvedToken ?? ""
            if key.isEmpty { continue }
            if seen.insert(key).inserted {
                Logger.info("PathDetector: matched '\(hit.str)' -> '\(key)'")
                results.append(path)
            }
        }

        // ─── Phase C: bare-filename regex. ─────────────────────────────────
        // Always runs (alongside Phase A+B). The regex itself is strict
        // (stem ≥3 chars, supported extension, word boundaries), and we cap
        // at 16 candidates as a backstop against pathological inputs.
        let maxBareCandidates = 16
        do {
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

    private func resolveCandidate(_ rawCandidate: String) -> DetectedPath? {
        // Strip sentence-ending punctuation that regexes commonly capture by
        // accident (e.g. "Check https://foo.com." → "https://foo.com").
        var candidate = rawCandidate
        while let last = candidate.last, ",.;!?\"')]".contains(last) {
            candidate.removeLast()
        }
        guard !candidate.isEmpty else { return nil }
        let lower = candidate.lowercased()
        let ext = mediaExtension(of: candidate)
        let isImage = imageExtensions.contains(ext)
        let isVideo = videoExtensions.contains(ext)
        let isMarkdown = markdownExtensions.contains(ext)
        let isText = textExtensions.contains(ext)
        let isPDF = pdfExtensions.contains(ext)
        let isOther = otherExtensions.contains(ext)

        // Repair common URL typos and surface scheme-less domains.
        let normalizedHTTP: String? = {
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                return candidate
            }
            if lower.hasPrefix("https//") { return "https://" + candidate.dropFirst("https//".count) }
            if lower.hasPrefix("http//")  { return "http://"  + candidate.dropFirst("http//".count) }
            // Bare-domain hits — must look like a host (contain a `.` in the
            // portion before the first `/`) and must not be a path-style
            // candidate. This prevents `xporn/README.md` from being treated
            // as a host with path.
            if !lower.hasPrefix("/"),
               !lower.hasPrefix("~"),
               !lower.hasPrefix("file://"),
               !lower.contains("://") {
                let firstSlash = lower.firstIndex(of: "/") ?? lower.endIndex
                let host = lower[..<firstSlash]
                if host.contains(".") {
                    return "https://" + candidate
                }
            }
            return nil
        }()

        if let scheme = normalizedHTTP {
            guard let url = parseLenientURL(scheme) else { return nil }
            if isImage    { return .remoteImage(url) }
            if isVideo    { return .remoteVideo(url) }
            if isMarkdown { return .remoteMarkdown(url) }
            if isText     { return .remoteText(url) }
            if isPDF      { return .remotePDF(url) }
            if isOther    { return .remoteOther(url) }
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
            // Heuristic: many users abbreviate home-rooted paths by dropping
            // the leading `~/`, e.g. "Desktop/work/Foo.pdf". Try expanding
            // against $HOME first; if that's a real file, surface it as a
            // concrete local hit so the user skips the Spotlight round-trip.
            let homeExpanded = (NSHomeDirectory() as NSString)
                .appendingPathComponent(candidate)
            if isValidLocalMedia(path: homeExpanded) {
                return localKind(for: homeExpanded)
            }
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
        if textExtensions.contains(ext)     { return .localText(url) }
        if pdfExtensions.contains(ext)      { return .localPDF(url) }
        if otherExtensions.contains(ext)    { return .localOther(url) }
        if imageExtensions.contains(ext)    { return .localImage(url) }
        // Fallback — extension matched the regex but isn't in any bucket
        // (shouldn't happen since the regex is built from these same sets).
        return .localOther(url)
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
