import Foundation
import AppKit
import os.log

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}

/// Coarse product metadata only: no hostname, serial number, account, paths or media.
enum ClientEnvironment {
    static var buildChannel: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
    static var eventProperties: [String: String] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return ["appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
                "appBuild": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
                "macOS": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                "architecture": architecture, "language": Preferences.shared.appLanguage.rawValue,
                "buildChannel": buildChannel]
    }
    static var summary: String {
        let p = eventProperties
        return "Glance \(p["appVersion"]!) (build \(p["appBuild"]!))\nmacOS \(p["macOS"]!)\nArchitecture: \(p["architecture"]!)\nLanguage: \(p["language"]!)\nChannel: \(buildChannel)"
    }
}

final class Logger {
    static let shared = Logger()

    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let osLog: OSLog
    private let queue = DispatchQueue(label: "com.glance.logger")
    private let maxLogFileSize: UInt64 = 5 * 1024 * 1024

    private init() {
        self.osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.glance", category: "App")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.dateFormatter = formatter

        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Glance", isDirectory: true)

        if let supportURL = appSupportURL {
            do {
                try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true, attributes: nil)
                let logURL = supportURL.appendingPathComponent("app.log")
                self.logFileURL = logURL

                if !fileManager.fileExists(atPath: logURL.path) {
                    fileManager.createFile(atPath: logURL.path, contents: nil, attributes: nil)
                }
            } catch {
                self.logFileURL = URL(fileURLWithPath: "/tmp/glance.log")
                os_log("Logger init failed, using fallback: %{public}@", log: osLog, type: .error, error.localizedDescription)
            }
        } else {
            self.logFileURL = URL(fileURLWithPath: "/tmp/glance.log")
            os_log("Could not get app support URL, using fallback", log: osLog, type: .error)
        }

        queue.async {
            self.writeToFile("=== Logger initialized ===")
        }
    }

    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.log(message, level: .debug, file: file, function: function, line: line)
    }

    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.log(message, level: .info, file: file, function: function, line: line)
    }

    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.log(message, level: .warning, file: file, function: function, line: line)
    }

    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.log(message, level: .error, file: file, function: function, line: line)
    }

    /// Selected text, clipboard contents, paths and URLs must pass through this.
    /// Release builds keep only the length; Debug builds keep the value.
    static func redact(_ value: String) -> String {
        #if DEBUG
        return value
        #else
        return "<redacted \(value.count) chars>"
        #endif
    }

    private func log(_ message: String, level: LogLevel, file: String = #file, function: String = #function, line: Int = #line) {
        #if !DEBUG
        if level == .debug { return }
        #endif

        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)"

        os_log("%{private}@", log: osLog, type: level.osLogType, logMessage)
        #if DEBUG
        Swift.print(logMessage)
        #endif

        queue.async {
            self.writeToFile(logMessage)
        }
    }

    private func writeToFile(_ message: String) {
        rotateIfNeeded()
        let fullMessage = message + "\n"
        if let data = fullMessage.data(using: .utf8) {
            do {
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    let handle = try FileHandle(forWritingTo: logFileURL)
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try fullMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                os_log("Failed to write log: %{public}@", log: osLog, type: .error, error.localizedDescription)
            }
        }
    }

    /// Keeps one previous generation (app.log.1) once app.log exceeds maxLogFileSize.
    private func rotateIfNeeded() {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? UInt64,
              size > maxLogFileSize else { return }
        let rotatedURL = logFileURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: rotatedURL)
        try? fileManager.moveItem(at: logFileURL, to: rotatedURL)
    }

    static func revealLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([shared.logFileURL])
    }

    static func getLogContents() -> String {
        (try? String(contentsOf: shared.logFileURL, encoding: .utf8)) ?? ""
    }

    static func clearLogs() {
        try? "".write(to: shared.logFileURL, atomically: true, encoding: .utf8)
    }

    static func exportDiagnostics(to url: URL, header: String, completion: @escaping (Error?) -> Void) {
        shared.queue.async {
            do {
                let data = (try? Data(contentsOf: shared.logFileURL)) ?? Data()
                let tail = String(decoding: data.suffix(256 * 1024), as: UTF8.self)
                let report = header + "\n--- Recent log (redacted; review before sharing) ---\n" + SupportDiagnostics.redact(tail)
                try report.write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }
}

enum SupportDiagnostics {
    static var reportTemplate: String {
        """
        \(ClientEnvironment.summary)

        \("Steps to reproduce:".localized)
        1.
        2.

        \("Expected result:".localized)

        \("Actual result:".localized)

        \("Screenshots (attach after review):".localized)

        \("Order number or Widget task ID (optional, private email only):".localized)

        \("Please review attachments before sending. Logs are never attached automatically. Do not post logs, email addresses, full order details or redemption codes publicly. We aim to reply within 1–2 business days.".localized)
        """
    }
    static func redact(_ input: String) -> String {
        var text = input.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "<home>")
        let rules = [
            (#"(?i)\b(?:https?|file)://[^\s<>\"']+"#, "<url>"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "<email>"),
            (#"(?i)\bGLG(?:[- ]?[A-HJ-NP-Z2-9]{4}){4}\b"#, "<redemption-code>"),
            (#"(?i)\bbearer\s+[^\s,;\"']+"#, "<credential>"),
            (#"(?i)\b(?:[a-z0-9_]*(?:token|secret|password)|authorization|api[_-]?key)[\"']?\s*[:=]\s*(?:\"[^\"]*\"|'[^']*'|[^\s,;]+)"#, "<credential>"),
            (#"(?:/Users|/Volumes|/private|/tmp|<home>)/[^\n]+"#, "<path>"),
            (#"(?i)\b(?:order|task)[_-][a-z0-9_-]{8,}\b"#, "<private-id>")
        ]
        for (pattern, replacement) in rules {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return text
    }
}
