import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image formats Glance can route into its image pipeline. The explicit
/// aliases cover common web, design, scientific, icon, texture, and camera
/// RAW extensions; ImageIO's runtime type list automatically adds formats
/// introduced by newer macOS releases without requiring an app update.
enum ImageFormatSupport {
    private static let explicitExtensions: Set<String> = [
        // Web and general-purpose raster
        "jpg", "jpeg", "jpe", "jfif", "png", "apng", "gif", "webp",
        "heic", "heif", "heics", "avif", "avifs", "jxl",
        "bmp", "dib", "tif", "tiff",
        // JPEG 2000 and multi-picture
        "jp2", "j2k", "jpf", "jpx", "jpm", "mj2", "mpo",
        // Vector, design, HDR, and legacy workstation formats
        "svg", "svgz", "psd", "psb", "ai", "eps", "exr", "hdr", "rgbe",
        "tga", "targa", "sgi", "rgb", "rgba", "bw", "pict", "pct", "pic",
        // Icons and GPU textures
        "ico", "cur", "icns", "dds", "ktx", "ktx2", "astc", "pvr",
        // Portable anymap family
        "pbm", "pgm", "ppm", "pnm",
        // Camera RAW families
        "3fr", "ari", "arw", "bay", "bmq", "cap", "cr2", "cr3", "crw",
        "cs1", "dc2", "dcr", "dng", "drf", "eip", "erf", "fff", "iiq",
        "k25", "kdc", "mdc", "mef", "mos", "mrw", "nef", "nrw", "obm",
        "orf", "pef", "ptx", "pxn", "qtk", "raf", "raw", "rdc", "rw2",
        "rwl", "rwz", "sr2", "srf", "srw", "x3f",
    ]

    private static let runtimeExtensions: Set<String> = {
        let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return Set(identifiers.compactMap { UTType($0)?.preferredFilenameExtension?.lowercased() })
    }()

    static let extensions = explicitExtensions.union(runtimeExtensions)

    static func supports(extension pathExtension: String) -> Bool {
        let ext = pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if extensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext), type.conforms(to: .image) else {
            return false
        }
        let decoders = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return decoders.contains(type.identifier)
    }
}

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
    /// "Other" file types — known files we can't preview inline (doc, zip,
    /// mp3, …). They show as a generic icon tile and click reveals
    /// them in Finder (local) or opens the URL in the browser (remote).
    case localOther(URL)
    case remoteOther(URL)
    case localFolder(URL)
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
             .localFolder(let url),
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
             .localFolder,
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
    private let imageExtensions = ImageFormatSupport.extensions
    private let videoExtensions: Set<String> = [
        // AVPlayer-native containers
        "mp4", "mov", "m4v", "mpg", "mpeg", "mpe", "m2v",
        "ts", "m2ts", "mts", "3gp", "3gpp", "3g2",
        // Accepted for drop/paste; playback may fail (failed state shows)
        "webm", "mkv", "avi"
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
        "html", "htm", "css", "scss", "sass", "less", "styl",
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
        // Design project formats that aren't directly image-decodable
        "sketch", "fig", "xd", "indd", "afdesign",
        // Audio
        "mp3", "m4a", "wav", "flac", "aac", "ogg", "opus", "aiff",
        // Archives / disk images
        "zip", "tar", "gz", "tgz", "bz2", "7z", "rar", "dmg", "iso",
        // Binaries / installers
        "exe", "app", "deb", "rpm", "pkg", "msi", "appimage",
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
    private let bareFilenameNoExtRegex: NSRegularExpression
    private let folderAbsolutePathRegex: NSRegularExpression
    private let folderHomePathRegex: NSRegularExpression
    /// A path fragment with at least one slash and no requirement on the last
    /// component: what a selection looks like when it stops mid-name.
    private let partialPathRegex: NSRegularExpression
    /// Shell-escaped characters (`My\ Photos`, `\(1\)`) as pasted from a terminal.
    private let shellEscapeRegex: NSRegularExpression
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
        // A comma is normally a delimiter (so "urlA,urlB" splits into two), but
        // some CDNs put commas *inside* the path (e.g. civitai's
        // ".../anim=false,width=450,optimized=true/x.jpeg"). So we accept a comma
        // only when it is NOT followed by whitespace/bracket and NOT followed by
        // another "https?://" — i.e. it's clearly mid-URL, not a separator.
        self.httpRegex = try! NSRegularExpression(
            // URL candidates are deliberately broad here. URL syntax allows
            // underscores, repeated hyphens, query punctuation and CDN
            // delimiters; resolveCandidate() performs the final trim and
            // media classification. The previous character-class expression
            // could prematurely stop on valid CDN URL characters.
            pattern: "https?:?//[^\\s\"'<>]+",
            options: []
        )
        // Bare domain without scheme — `www.foo.com[/...]` or `something.com[/...]`.
        // Restricted to a www. prefix or a known multi-letter TLD to bound
        // false-positive risk against ordinary prose with periods.
        self.bareDomainRegex = try! NSRegularExpression(    
            pattern: "(?<![A-Za-z0-9._/@-])(?:www\\.[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+|[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.(?:com|net|org|io|ai|app|dev|co|me|info|xyz|page|site|store|tech|gov|edu))(?:/[^\\s\"'<>()\\[\\]{},\\\\]*)?(?![A-Za-z0-9])",
            options: []
        )
        // Comma is excluded so comma-separated lists of paths (e.g.
        // "/a/x.png,/b/y.png") are split cleanly into separate matches.
        // Whitespace inside the character class is intentionally allowed
        // (no `\s` exclusion) so paths like "/Users/me/Desktop/Project
        // Access Guide.pdf" still match. The lazy `+?` minimises greediness
        // and `isValidLocalMedia` filters any over-extended candidate via
        // file-existence check. Newlines and tabs remain excluded so
        // matches can't span lines.
        self.fileURLRegex = try! NSRegularExpression(
            pattern: "file://[^\"'<>()\\[\\]{},\\n\\r\\t\\\\]+?\\.(?i:\(extAlt))",
            options: []
        )
        self.absolutePathRegex = try! NSRegularExpression(
            pattern: "/[^\"'<>()\\[\\]{},\\n\\r\\t\\\\]+?\\.(?i:\(extAlt))",
            options: []
        )
        self.homePathRegex = try! NSRegularExpression(
            pattern: "~/[^\"'<>()\\[\\]{},\\n\\r\\t\\\\]+?\\.(?i:\(extAlt))",
            options: []
        )
        // Relative path: at least one interior '/', optional ./ or ../ prefix.
        // Lookbehind avoids overlap with absolute/home/file:// regexes.
        // The second segment (after the first slash) allows spaces and tabs
        // so paths like "Desktop/work/Project Access Guide.pdf" match. The
        // first segment stays strict — letting it eat spaces would devour
        // narrative text leading up to the slash.
        self.relativePathRegex = try! NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}_/~])(?:\\./|\\.\\./)*[\\p{L}\\p{N}_.\\-]+/[\\p{L}\\p{N}_./\\- \\t]+?\\.(?i:\(extAlt))(?![\\p{L}\\p{N}])",
            options: []
        )
        // Bare filename: stem ≥2 chars, alphanumeric/_/-/., must be standalone
        // (not preceded by slashes, tildes, dots, dashes, or alphanumerics).
        self.bareFilenameRegex = try! NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}_./~\\-])([\\p{L}\\p{N}_][\\p{L}\\p{N}_.\\- ]+?\\.(?i:\(extAlt))(?![\\p{L}\\p{N}]))(?:\\]?[ \\t]*\\()?",
            options: []
        )
        self.bareFilenameNoExtRegex = try! NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}_./~\\-])[\\p{L}\\p{N}_][\\p{L}\\p{N}_\\-]{2,29}(?![\\p{L}\\p{N}])",
            options: []
        )
        self.folderAbsolutePathRegex = try! NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}_.~\\-])/(?:Users|System|Library|Applications|Volumes|private|tmp|var|usr|bin|sbin|opt|dev|etc|home)/[^\"'<>()\\[\\]{},\\n\\r\\t \\\\]+(?:/[^\"'<>()\\[\\]{},\\n\\r\\t \\\\]+)*",
            options: []
        )
        self.folderHomePathRegex = try! NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}_.~\\-])~/[^\"'<>()\\[\\]{},\\n\\r\\t \\\\]+(?:/[^\"'<>()\\[\\]{},\\n\\r\\t \\\\]+)*",
            options: []
        )

        // First component strict (no spaces), later ones may contain single
        // spaces between words. Completion trims trailing words that turn out
        // to be prose.
        self.partialPathRegex = try! NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}_./~\\-])(?:~/|/|\\./|\\.\\./)?[\\p{L}\\p{N}_.\\-]+(?:/[\\p{L}\\p{N}_.\\-]+(?: [\\p{L}\\p{N}_.\\-]+)*)+",
            options: []
        )
        self.shellEscapeRegex = try! NSRegularExpression(pattern: "\\\\([ ()&'\"\\[\\]{}!$;])", options: [])

        self.allRegexes = [httpRegex, fileURLRegex, homePathRegex, absolutePathRegex]
    }

    /// Whether files with this extension are something Glance can open.
    func supportsExtension(_ ext: String) -> Bool {
        localSupportedExtensions.contains(ext.lowercased())
    }

    /// A bare name cut off before its end (`kyoto-da`, `hero.pn`), completed
    /// against the folders the selection most likely refers to.
    func completeName(_ prefix: String, in directories: [URL]) -> [DetectedPath] {
        PathCompleter.completeName(prefix, in: directories, accepts: supportsExtension)
            .map { localKind(for: $0.path) }
    }

    /// Terminals escape spaces and brackets with backslashes; drop the
    /// backslashes so the regexes see the real path.
    private func unescapingShell(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        return shellEscapeRegex.stringByReplacingMatches(in: text, options: [],
                                                         range: NSRange(location: 0, length: (text as NSString).length),
                                                         withTemplate: "$1")
    }

    func detect(_ text: String) -> DetectedPath {
        return detectAll(text).first ?? .invalid
    }

    /// `contextDirectories` are the folders a relative fragment is tried in
    /// (the terminal's working directory and the like), closest first.
    func detectAll(_ text: String, contextDirectories: [URL] = []) -> [DetectedPath] {
        let trimmed = unescapingShell(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return [] }

        Logger.info("PathDetector: scanning text='\(Logger.redact(truncate(trimmed)))'")

        func hasConcrete(_ paths: [DetectedPath]) -> Bool { paths.contains { $0.url != nil } }
        var results = collectAll(in: joiningWrappedMediaURLs(trimmed))
        if !hasConcrete(results) {
            // Editors with soft-wrap and multi-line OCR output frequently
            // break a long URL/path in the middle. Retry with line breaks and
            // surrounding spaces removed; a real file found that way beats
            // bare-name guesses from the broken halves.
            let unwrapped = unwrapLines(trimmed)
            if unwrapped != trimmed {
                Logger.info("PathDetector: retrying unwrapped='\(Logger.redact(truncate(unwrapped)))'")
                let joined = collectAll(in: unwrapped)
                if hasConcrete(joined) || results.isEmpty { results = joined }
            }
        }
        if !hasConcrete(results) {
            // The selection may stop before the end of the path: finish it on disk.
            let completed = completePartialPaths(in: trimmed, contextDirectories: contextDirectories)
            if !completed.isEmpty {
                Logger.info("PathDetector: completed \(completed.count) cut-off path(s)")
                results = completed
            }
        }

        Logger.info("PathDetector: detected \(results.count) image candidate(s)")
        return results
    }

    /// Path fragments in `text` completed like a shell's Tab: `~/Desk/hero.pn`
    /// → `~/Desktop/hero.png`. Relative fragments try the context folders, then
    /// the usual places. Trailing words are dropped one at a time in case the
    /// fragment ran into prose.
    private func completePartialPaths(in text: String, contextDirectories: [URL]) -> [DetectedPath] {
        let ns = text as NSString
        var tokens: [String] = []
        partialPathRegex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard let m else { return }
            tokens.append(ns.substring(with: m.range))
            if tokens.count >= 8 { stop.pointee = true }
        }
        guard !tokens.isEmpty else { return [] }

        let home = URL(fileURLWithPath: UserHome.path, isDirectory: true)
        let roots = Self.orderedUnique(contextDirectories + ["Desktop", "Downloads", "Documents", "Pictures"]
            .map { home.appendingPathComponent($0, isDirectory: true) } + [home])

        var results: [DetectedPath] = []
        var seen = Set<String>()
        for token in tokens {
            var candidate = token
            for _ in 0..<4 {
                let urls = PathCompleter.complete(candidate, roots: roots, accepts: supportsExtension)
                if !urls.isEmpty {
                    for url in urls where seen.insert(url.standardizedFileURL.path).inserted {
                        results.append(localKind(for: url.path))
                    }
                    break
                }
                // "Photos/kyo is here" → "Photos/kyo"
                guard let space = candidate.lastIndex(of: " ") else { break }
                candidate = String(candidate[..<space])
            }
            if results.count >= PathCompleter.limit { break }
        }
        return results
    }

    private static func orderedUnique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func collectAll(in text: String) -> [DetectedPath] {
        struct Hit { let range: NSRange; let str: String; let priority: Int }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        let prioritized: [(NSRegularExpression, Int)] = [
            (httpRegex, 0),
            (fileURLRegex, 1),
            (homePathRegex, 2),
            (absolutePathRegex, 3),
            (bareDomainRegex, 1),
        ]
        var hits: [Hit] = []
        for (regex, prio) in prioritized {
            regex.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
                guard let m = m else { return }
                hits.append(Hit(range: m.range, str: ns.substring(with: m.range), priority: prio))
            }
        }

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
        var consumed = IndexSet()
        var filenamesByPathStart: [Int: String] = [:]
        var lastEnd = 0
        for hit in hits {
            if hit.range.location < lastEnd { continue }
            // Only "consume" range when the candidate actually validates —
            // an over-extended absolute-path match that doesn't exist on
            // disk shouldn't block shorter strict matches that follow.
            var resolvedPath = resolveCandidate(hit.str)
            var consumeEnd = hit.range.location + hit.range.length

            // Lazy regex can under-match absolute / home / file:// paths that
            // contain a dot before the real extension, e.g.
            // "/.claude/settings.json" → "/Users/.../.c".  When the short
            // candidate fails validation, try extending to the next word
            // boundary in the original text.
            if resolvedPath == nil,
               hit.str.hasPrefix("/") || hit.str.hasPrefix("~/") || hit.str.hasPrefix("file://") {
                let ns = text as NSString
                let tailStart = hit.range.location + hit.range.length
                let tailLen = ns.length - tailStart
                if tailLen > 0 {
                    let tail = ns.substring(with: NSRange(location: tailStart, length: tailLen))
                    let boundary = CharacterSet.whitespacesAndNewlines
                        .union(CharacterSet(charactersIn: "\"'<>()[]{},;!?"))
                    let extra: String
                    if let idx = tail.unicodeScalars.firstIndex(where: { boundary.contains($0) }) {
                        let pos = tail.distance(from: tail.startIndex, to: idx)
                        extra = String(tail.prefix(pos))
                    } else {
                        extra = tail
                    }
                    if !extra.isEmpty {
                        let extended = hit.str + extra
                        if let p = resolveCandidate(extended) {
                            resolvedPath = p
                            consumeEnd = tailStart + extra.utf16.count
                        }
                    }
                }
            }

            guard let path = resolvedPath else { continue }
            filenamesByPathStart[hit.range.location] = path.url?.lastPathComponent
                ?? path.unresolvedToken.map { ($0 as NSString).lastPathComponent }
            consumed.insert(integersIn: hit.range.location..<consumeEnd)
            lastEnd = consumeEnd
            // Dedup: concrete cases use URL string; unresolved cases use token.
            let key = path.url?.absoluteString ?? path.unresolvedToken ?? ""
            if key.isEmpty { continue }
            if seen.insert(key).inserted {
                Logger.info("PathDetector: matched '\(Logger.redact(hit.str))' -> '\(Logger.redact(key))'")
                results.append(path)
            }
        }

        if results.isEmpty {
            let folderHits = collectFolderHits(in: text, range: full)
            for hit in folderHits {
                if hit.range.location < lastEnd { continue }
                if let path = resolveFolderCandidate(hit.str) {
                    let key = path.url?.absoluteString ?? ""
                    if !key.isEmpty && seen.insert(key).inserted {
                        Logger.info("PathDetector: folder match '\(Logger.redact(hit.str))' -> '\(Logger.redact(key))'")
                        results.append(path)
                        lastEnd = hit.range.location + hit.range.length
                    }
                }
            }
        }

        let maxBareCandidates = 16
        var bareCount = 0
        bareFilenameRegex.enumerateMatches(in: text, options: [], range: full) { m, _, stop in
            guard let m = m else { return }
            guard !consumed.intersects(integersIn: m.range.location..<NSMaxRange(m.range)) else { return }
            let token = ns.substring(with: m.range(at: 1))
            // A table can spell one link as "name.gif (folder/name.gif)"
            // or "[name.gif](folder/name.gif)". Only resolve the target.
            if NSMaxRange(m.range) > NSMaxRange(m.range(at: 1)),
               filenamesByPathStart[NSMaxRange(m.range)] == token { return }
            if seen.insert(token).inserted {
                Logger.info("PathDetector: bare filename candidate '\(Logger.redact(token))'")
                results.append(.unresolvedFilename(token))
                bareCount += 1
                if bareCount >= maxBareCandidates {
                    stop.pointee = true
                }
            }
        }

        if results.isEmpty {
            let maxNoExtCandidates = 3
            var noExtCount = 0
            bareFilenameNoExtRegex.enumerateMatches(in: text, options: [], range: full) { m, _, stop in
                guard let m = m else { return }
                let token = ns.substring(with: m.range)
                if token.count >= 3 && token.count <= 30 && seen.insert(token).inserted {
                    Logger.info("PathDetector: no-ext candidate '\(Logger.redact(token))'")
                    results.append(.unresolvedFilename(token))
                    noExtCount += 1
                    if noExtCount >= maxNoExtCandidates {
                        stop.pointee = true
                    }
                }
            }
        }

        return results
    }

    private func resolveCandidate(_ rawCandidate: String) -> DetectedPath? {
        var candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        // Terminal/window-monitor diagnostics often append Python-style
        // metadata immediately after the URL, e.g. `image.png[' bounds=...`.
        // Treat the opening bracket as trailing annotation punctuation too;
        // otherwise the extension becomes `png[` and image classification
        // fails even though the URL itself is valid.
        while let last = candidate.last, ",.;!?\"'()[{]}\\，。；：！？、".contains(last) {
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
            let expanded = UserHome.expandingTilde(candidate)
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
            let homeExpanded = (UserHome.path as NSString)
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

    /// Classify a local file path into the correct DetectedPath kind based
    /// on its extension.  Public so AppDelegate can reuse it when rehydrating
    /// Spotlight results.
    func localKind(for path: String) -> DetectedPath {
        let ext = (path as NSString).pathExtension.lowercased()
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
            if !isPackage { return .localFolder(url) }
        }
        if videoExtensions.contains(ext)    { return .localVideo(url) }
        if ImageFormatSupport.supports(extension: ext) { return .localImage(url) }
        if markdownExtensions.contains(ext) { return .localMarkdown(url) }
        if textExtensions.contains(ext)     { return .localText(url) }
        if pdfExtensions.contains(ext)      { return .localPDF(url) }
        if otherExtensions.contains(ext)    { return .localOther(url) }
        return .localOther(url)
    }

    private func mediaExtension(of candidate: String) -> String {
        // Prefer the path extension when present.
        var withoutQuery = String(candidate.prefix { $0 != "?" && $0 != "#" })
        while withoutQuery.hasSuffix("\\") {
            withoutQuery.removeLast()
        }
        let pathExtension = (withoutQuery as NSString).pathExtension.lowercased()
        if !pathExtension.isEmpty { return pathExtension }

        // CDNs frequently serve extensionless paths and put the output format
        // in the query. Support both standard `format=jpg` (pbs.twimg.com) and
        // path-like transforms such as `/format/webp|...` (xhscdn.com).
        if let queryStart = candidate.firstIndex(of: "?") {
            let query = String(candidate[candidate.index(after: queryStart)...]).lowercased()
            let patterns = [
                #"(?:^|[&/])(?:format|fm|ext)[=/]([a-z0-9]+)"#,
                #"(?:^|[&/])(?:format|fm|ext)=([a-z0-9]+)"#,
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
                      let range = Range(match.range(at: 1), in: query) else { continue }
                return String(query[range])
            }
        }
        return Self.extensionFromBangSuffix(of: withoutQuery)
    }

    /// Xiaohongshu-style CDN marker: the basename ends with a `!` section
    /// carrying the real format, e.g. `...!nc_n_webp_mw_1`, `...!nd_jpg_2`.
    /// Only the `!` tail is scanned so ordinary webpage slugs containing a
    /// format word (e.g. "my-png-collection") are not misclassified.
    static func extensionFromBangSuffix(of path: String) -> String {
        guard let bang = path.lastIndex(of: "!") else { return "" }
        let tail = path[path.index(after: bang)...].lowercased()
        // Longer tokens first so "jpeg" wins over "jpg".
        for token in ["jpeg", "webp", "heic", "heif", "tiff", "avif", "jxl",
                      "svg", "jp2", "webm", "png", "jpg", "gif", "bmp",
                      "mp4", "mov", "m4v", "mkv", "avi"] {
            if tail.contains(token) { return token }
        }
        return ""
    }

    /// Extensionless media and ordinary pages can have identical URL shapes.
    /// Ask for headers only, preserving the original URL and selection order.
    func classifyRemoteLinks(_ paths: [DetectedPath], session: URLSession = .shared,
                             completion: @escaping ([DetectedPath]) -> Void) {
        let group = DispatchGroup()
        var classified = paths
        var needsHeaders = false
        for (index, path) in paths.enumerated() {
            guard case .webPage(let url) = path else { continue }
            needsHeaders = true
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            group.enter()
            session.dataTask(with: request) { _, response, _ in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode), let mime = http.mimeType?.lowercased()
                    else { return }
                    if mime.hasPrefix("image/") { classified[index] = .remoteImage(url) }
                    if mime.hasPrefix("video/") { classified[index] = .remoteVideo(url) }
                }
            }.resume()
        }
        if needsHeaders {
            group.notify(queue: .main) { completion(classified) }
        } else {
            completion(paths)
        }
    }

    /// Terminal selections can contain a physical newline inside a URL. A
    /// truncated UUID still looks like a valid webpage, so the generic retry
    /// for selections with no concrete hits cannot recover it.
    private func joiningWrappedMediaURLs(_ text: String) -> String {
        guard text.contains(where: \.isNewline) else { return text }
        var lines = text.components(separatedBy: .newlines)
        for index in lines.indices.dropFirst() {
            let fragment = lines[index].trimmingCharacters(in: .whitespaces)
            guard !fragment.isEmpty, !fragment.contains(where: \.isWhitespace),
                  !fragment.contains("://"), !fragment.hasPrefix("/"), !fragment.hasPrefix("~"),
                  let match = httpRegex.matches(in: lines[index - 1],
                      range: NSRange(lines[index - 1].startIndex..., in: lines[index - 1])).last,
                  let range = Range(match.range, in: lines[index - 1]) else { continue }
            let line = lines[index - 1]
            guard line[range.upperBound...].allSatisfy(\.isWhitespace) else { continue }
            let prefix = String(line[range])
            guard case .webPage(let partialURL)? = resolveCandidate(prefix),
                  let joined = resolveCandidate(prefix + fragment), let url = joined.url else { continue }
            // A page URL followed by a separate filename is also a valid
            // selection. Join only a split extension or a split UUID basename.
            let basename = url.deletingPathExtension().lastPathComponent
            guard fragment.hasPrefix(".") ||
                    (UUID(uuidString: basename) != nil && basename.hasPrefix(partialURL.lastPathComponent)
                     && !partialURL.lastPathComponent.isEmpty) else { continue }
            switch joined {
            case .remoteImage, .remoteVideo:
                lines[index] = String(line[..<range.upperBound]) + fragment
                lines[index - 1] = ""
            default: break
            }
        }
        return lines.joined(separator: "\n")
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
            Logger.info("PathDetector: file does not exist at '\(Logger.redact(path))'")
            return false
        }
        if isDirectory.boolValue {
            let url = URL(fileURLWithPath: path)
            let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
            if isPackage {
                return true
            }
            let ext = (path as NSString).pathExtension.lowercased()
            return localSupportedExtensions.contains(ext)
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return localSupportedExtensions.contains(ext)
    }

    private func collectFolderHits(in text: String, range: NSRange) -> [(range: NSRange, str: String)] {
        var hits: [(range: NSRange, str: String)] = []
        let ns = text as NSString
        let regexes = [folderAbsolutePathRegex, folderHomePathRegex]
        for regex in regexes {
            regex.enumerateMatches(in: text, options: [], range: range) { m, _, _ in
                guard let m = m else { return }
                hits.append((range: m.range, str: ns.substring(with: m.range)))
            }
        }
        hits.sort { $0.range.location < $1.range.location }
        return hits
    }

    private func resolveFolderCandidate(_ rawCandidate: String) -> DetectedPath? {
        var candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = candidate.last, ",.;!?\"')]}\\".contains(last) {
            candidate.removeLast()
        }
        guard !candidate.isEmpty else { return nil }

        let path: String
        if candidate.hasPrefix("file://") {
            guard let url = parseLenientURL(candidate) else { return nil }
            path = url.path
        } else if candidate.hasPrefix("~/") {
            path = UserHome.expandingTilde(candidate)
        } else if candidate.hasPrefix("/") {
            path = candidate
        } else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        guard !isPackage else { return nil }

        let ext = (path as NSString).pathExtension.lowercased()
        guard ext.isEmpty || !localSupportedExtensions.contains(ext) else {
            return nil
        }

        return .localFolder(url)
    }

    private func truncate(_ s: String, max: Int = 200) -> String {
        if s.count <= max { return s }
        let prefix = s.prefix(max)
        return "\(prefix)…(\(s.count - max) more chars)"
    }
}
