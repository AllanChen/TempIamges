import Foundation

extension String {
    var localized: String {
        LanguageService.translation(for: self)
    }

    func localized(comment: String) -> String {
        localized
    }
}

enum LanguageService {
    private static var cachedDict: [String: String]?
    private static var cachedLang: String?

    static func translation(for key: String) -> String {
        let current = Preferences.shared.appLanguage.rawValue

        if cachedLang != current {
            cachedDict = loadStrings(for: current)
            cachedLang = current
        }

        if let value = cachedDict?[key], !value.isEmpty {
            return value
        }

        // Fallback to English if translation missing
        if current != "en" {
            if let enDict = loadStrings(for: "en"), let value = enDict[key], !value.isEmpty {
                return value
            }
        }

        return key
    }

    private static func loadStrings(for language: String) -> [String: String]? {
        let candidates: [String]
        if let lprojPath = Bundle.main.path(forResource: language, ofType: "lproj") {
            candidates = [(lprojPath as NSString).appendingPathComponent("Localizable.strings")]
        } else {
            candidates = []
        }

        let bundlePath = Bundle.main.bundlePath
        let fallbackPaths = [
            (bundlePath as NSString).appendingPathComponent("Contents/Resources/\(language).lproj/Localizable.strings"),
            (bundlePath as NSString).appendingPathComponent("../Resources/\(language).lproj/Localizable.strings"),
            (bundlePath as NSString).appendingPathComponent("../../Resources/\(language).lproj/Localizable.strings"),
        ]

        for path in candidates + fallbackPaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let dict = NSDictionary(contentsOfFile: path) as? [String: String]
            NSLog("[LanguageService] Loaded \(dict?.count ?? 0) strings for \(language) from \(path)")
            return dict
        }

        NSLog("[LanguageService] Failed to find Localizable.strings for: \(language)")
        return nil
    }

    static func invalidateCache() {
        cachedDict = nil
        cachedLang = nil
    }
}
