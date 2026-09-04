import Foundation

/// Local-only aggregate counters for validating Peek reliability. No selected
/// text, URLs, paths, filenames, or source application names are recorded.
enum PeekDiagnostics {
    private static let defaults = UserDefaults.standard
    private static let prefix = "com.glance.diagnostics."

    static func recordTrigger() { increment("triggers") }
    static func recordSuccess(latency: TimeInterval) {
        increment("successfulPreviews")
        defaults.set(defaults.double(forKey: prefix + "totalFirstFrameLatency") + latency,
                     forKey: prefix + "totalFirstFrameLatency")
    }
    static func recordUnrecognizedSelection() { increment("unrecognizedSelections") }
    static func recordMissingFile() { increment("missingFiles") }
    static func recordLoadFailure() { increment("loadFailures") }
    static func recordInspectTransition() { increment("inspectTransitions") }

    private static func increment(_ key: String) {
        let fullKey = prefix + key
        defaults.set(defaults.integer(forKey: fullKey) + 1, forKey: fullKey)
    }
}
