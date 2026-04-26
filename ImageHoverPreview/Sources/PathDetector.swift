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

    func detect(_ text: String) -> DetectedPath {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("PathDetector: Original text='\(trimmed)'")
        
        if trimmed.hasSuffix("'") || trimmed.hasSuffix("\"") {
            print("PathDetector: Removing trailing quote")
            trimmed.removeLast()
        }
        if trimmed.hasPrefix("'") || trimmed.hasPrefix("\"") {
            print("PathDetector: Removing leading quote")
            trimmed.removeFirst()
        }
        
        print("PathDetector: Checking text='\(trimmed)'")

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return detectImageURL(trimmed)
        }

        if trimmed.hasPrefix("file://") {
            return detectFileURL(trimmed)
        }

        if trimmed.hasPrefix("/") {
            return detectLocalPath(trimmed)
        }

        if trimmed.hasPrefix("~/") {
            let expanded = expandHomeDirectory(trimmed)
            return detectLocalPath(expanded)
        }

        print("PathDetector: No valid prefix found")
        return .invalid
    }

    private func detectImageURL(_ urlString: String) -> DetectedPath {
        guard let url = URL(string: urlString) else {
            print("PathDetector: Failed to create URL from '\(urlString)'")
            return .invalid
        }

        let path = url.path.isEmpty ? urlString : url.path
        let ext = (path as NSString).pathExtension.lowercased()
        
        print("PathDetector: URL path='\(path)', extension='\(ext)'")

        if supportedExtensions.contains(ext) {
            print("PathDetector: Found image URL '\(urlString)'")
            return .remoteImage(url)
        }

        print("PathDetector: Unsupported extension '\(ext)'")
        return .invalid
    }

    private func detectFileURL(_ urlString: String) -> DetectedPath {
        guard let url = URL(string: urlString) else {
            return .invalid
        }

        let path = url.path

        guard let homeDir = FileManager.default.homeDirectoryForCurrentUser.path as String?,
              path.hasPrefix(homeDir) else {
            return .invalid
        }

        return detectLocalPath(path)
    }

    private func detectLocalPath(_ path: String) -> DetectedPath {
        if path.contains("..") {
            return .invalid
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .invalid
        }

        guard !isDirectory.boolValue else {
            return .invalid
        }

        let ext = (path as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return .invalid
        }

        let url = URL(fileURLWithPath: path)
        return .localImage(url)
    }

    private func expandHomeDirectory(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return expanded
    }
}
