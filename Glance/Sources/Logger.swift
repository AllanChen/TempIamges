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

final class Logger {
    static let shared = Logger()

    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let osLog: OSLog
    private let queue = DispatchQueue(label: "com.imagehoverpreview.logger")

    private init() {
        self.osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.imagehoverpreview", category: "App")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.dateFormatter = formatter

        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ImageHoverPreview", isDirectory: true)

        if let supportURL = appSupportURL {
            do {
                try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true, attributes: nil)
                let logURL = supportURL.appendingPathComponent("app.log")
                self.logFileURL = logURL

                if !fileManager.fileExists(atPath: logURL.path) {
                    fileManager.createFile(atPath: logURL.path, contents: nil, attributes: nil)
                }
            } catch {
                self.logFileURL = URL(fileURLWithPath: "/tmp/imagehoverpreview.log")
                os_log("Logger init failed, using fallback: %{public}@", log: osLog, type: .error, error.localizedDescription)
            }
        } else {
            self.logFileURL = URL(fileURLWithPath: "/tmp/imagehoverpreview.log")
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

    private func log(_ message: String, level: LogLevel, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)"

        os_log("%{public}@", log: osLog, type: level.osLogType, logMessage)
        Swift.print(logMessage)

        queue.async {
            self.writeToFile(logMessage)
        }
    }

    private func writeToFile(_ message: String) {
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

    static func revealLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([shared.logFileURL])
    }

    static func getLogContents() -> String {
        (try? String(contentsOf: shared.logFileURL, encoding: .utf8)) ?? ""
    }

    static func clearLogs() {
        try? "".write(to: shared.logFileURL, atomically: true, encoding: .utf8)
    }
}
