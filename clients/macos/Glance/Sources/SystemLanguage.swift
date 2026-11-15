import Foundation

/// Picks Glance's language from the system's language list. Glance supports English, Simplified Chinese,
/// Japanese and German; any other system language (including Traditional Chinese) falls back to English.
enum SystemLanguage {
    /// The Glance language code (`en`, `zh-Hans`, `ja` or `de`) for a list of system language identifiers
    /// such as `["zh-Hans-CN", "en-US"]`. Only the first (the primary) language counts.
    static func code(for identifiers: [String]) -> String {
        guard let first = identifiers.first else { return "en" }
        let parts = first.replacingOccurrences(of: "_", with: "-").lowercased()
            .split(separator: "-").map(String.init)
        switch parts.first {
        case "ja": return "ja"
        case "de": return "de"
        case "zh":
            // Simplified Chinese only. Traditional (zh-Hant, or the TW / HK / MO regions) is not supported.
            if parts.contains("hans") { return "zh-Hans" }
            let traditional = parts.contains("hant") || parts.contains("tw") || parts.contains("hk") || parts.contains("mo")
            return traditional ? "en" : "zh-Hans"
        default: return "en"
        }
    }

    /// The system's own language list, not Glance's override: Glance writes its chosen language into its own
    /// `AppleLanguages`, which `Locale.preferredLanguages` would then return instead of the system's.
    static func systemIdentifiers() -> [String] {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        if let global, !global.isEmpty { return global }
        return Locale.preferredLanguages
    }
}
