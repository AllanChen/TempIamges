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

    private let extensionPattern: String
    private let httpRegex: NSRegularExpression
    private let fileURLRegex: NSRegularExpression
    private let absolutePathRegex: NSRegularExpression
    private let homePathRegex: NSRegularExpression

    init() {
        let exts = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"]
        let extAlt = exts.joined(separator: "|")
        self.extensionPattern = extAlt

        // URLs may include query strings; allow optional ?... before end-anchor of the extension match.
        self.httpRegex = try! NSRegularExpression(
            pattern: "https?://[^\\s\"'<>()]+?\\.(?i:\(extAlt))(?:\\?[^\\s\"'<>]*)?",
            options: []
        )
        self.fileURLRegex = try! NSRegularExpression(
            pattern: "file://[^\\s\"'<>()]+?\\.(?i:\(extAlt))",
            options: []
        )
        // POSIX absolute path: starts with / and contains a supported image extension.
        self.absolutePathRegex = try! NSRegularExpression(
            pattern: "/[^\\s\"'<>()]+?\\.(?i:\(extAlt))",
            options: []
        )
        // Tilde-prefixed home path.
        self.homePathRegex = try! NSRegularExpression(
            pattern: "~/[^\\s\"'<>()]+?\\.(?i:\(extAlt))",
            options: []
        )
    }

    func detect(_ text: String) -> DetectedPath {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }

        print("PathDetector: scanning text='\(trimmed)'")

        // 1) Remote http/https image URL anywhere in text.
        if let match = firstMatch(in: trimmed, regex: httpRegex) {
            print("PathDetector: matched http URL='\(match)'")
            if let url = URL(string: match) {
                return .remoteImage(url)
            }
        }

        // 2) file:// URL.
        if let match = firstMatch(in: trimmed, regex: fileURLRegex) {
            print("PathDetector: matched file URL='\(match)'")
            if let url = URL(string: match) {
                let path = url.path
                if isValidLocalImage(path: path) {
                    return .localImage(URL(fileURLWithPath: path))
                }
            }
        }

        // 3) Tilde-prefixed home path (check before absolute since it doesn't start with /).
        if let match = firstMatch(in: trimmed, regex: homePathRegex) {
            let expanded = (match as NSString).expandingTildeInPath
            print("PathDetector: matched ~/ path='\(match)' -> '\(expanded)'")
            if isValidLocalImage(path: expanded) {
                return .localImage(URL(fileURLWithPath: expanded))
            }
        }

        // 4) Absolute POSIX path.
        if let match = firstMatch(in: trimmed, regex: absolutePathRegex) {
            print("PathDetector: matched absolute path='\(match)'")
            if isValidLocalImage(path: match) {
                return .localImage(URL(fileURLWithPath: match))
            }
        }

        print("PathDetector: no image path found in text")
        return .invalid
    }

    private func firstMatch(in text: String, regex: NSRegularExpression) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range, in: text) else {
            return nil
        }
        return String(text[r])
    }

    private func isValidLocalImage(path: String) -> Bool {
        if path.contains("..") {
            return false
        }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            print("PathDetector: file does not exist at '\(path)'")
            return false
        }
        guard !isDirectory.boolValue else {
            return false
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }
}
