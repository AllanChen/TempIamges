import Foundation

/// Persisted record of a single hotkey-triggered preview event.
///
/// We store the raw selected text plus the URLs / tokens that PathDetector
/// surfaced, so the History window can render them later without re-running
/// detection (and without depending on the source app or selection still
/// being live).
struct HistoryRecord: Codable {
    let timestamp: Date
    let selectedText: String
    let items: [Item]

    struct Item: Codable {
        enum Kind: String, Codable {
            case localImage, remoteImage
            case localVideo, remoteVideo
            case localMarkdown, remoteMarkdown
            case localText, remoteText
            case localPDF, remotePDF
            case localOther, remoteOther
            case localFolder
            case webPage
            case unresolvedFilename, unresolvedRelativePath
        }
        let kind: Kind
        /// Absolute URL string for resolved cases; raw token for unresolved.
        let value: String

        static func from(_ path: DetectedPath) -> Item? {
            switch path {
            case .localImage(let url):     return Item(kind: .localImage, value: url.absoluteString)
            case .remoteImage(let url):    return Item(kind: .remoteImage, value: url.absoluteString)
            case .localVideo(let url):     return Item(kind: .localVideo, value: url.absoluteString)
            case .remoteVideo(let url):    return Item(kind: .remoteVideo, value: url.absoluteString)
            case .localMarkdown(let url):  return Item(kind: .localMarkdown, value: url.absoluteString)
            case .remoteMarkdown(let url): return Item(kind: .remoteMarkdown, value: url.absoluteString)
            case .localText(let url):      return Item(kind: .localText, value: url.absoluteString)
            case .remoteText(let url):     return Item(kind: .remoteText, value: url.absoluteString)
            case .localPDF(let url):       return Item(kind: .localPDF, value: url.absoluteString)
            case .remotePDF(let url):      return Item(kind: .remotePDF, value: url.absoluteString)
            case .localOther(let url):     return Item(kind: .localOther, value: url.absoluteString)
            case .remoteOther(let url):    return Item(kind: .remoteOther, value: url.absoluteString)
            case .localFolder(let url):    return Item(kind: .localFolder, value: url.absoluteString)
            case .webPage(let url):        return Item(kind: .webPage, value: url.absoluteString)
            case .unresolvedFilename(let s):     return Item(kind: .unresolvedFilename, value: s)
            case .unresolvedRelativePath(let s): return Item(kind: .unresolvedRelativePath, value: s)
            case .invalid:                 return nil
            }
        }

        var detectedPath: DetectedPath? {
            switch kind {
            case .localImage:     return URL(string: value).map { .localImage($0) }
            case .remoteImage:    return URL(string: value).map { .remoteImage($0) }
            case .localVideo:     return URL(string: value).map { .localVideo($0) }
            case .remoteVideo:    return URL(string: value).map { .remoteVideo($0) }
            case .localMarkdown:  return URL(string: value).map { .localMarkdown($0) }
            case .remoteMarkdown: return URL(string: value).map { .remoteMarkdown($0) }
            case .localText:      return URL(string: value).map { .localText($0) }
            case .remoteText:     return URL(string: value).map { .remoteText($0) }
            case .localPDF:       return URL(string: value).map { .localPDF($0) }
            case .remotePDF:      return URL(string: value).map { .remotePDF($0) }
            case .localOther:     return URL(string: value).map { .localOther($0) }
            case .remoteOther:    return URL(string: value).map { .remoteOther($0) }
            case .localFolder:    return URL(string: value).map { .localFolder($0) }
            case .webPage:        return URL(string: value).map { .webPage($0) }
            case .unresolvedFilename:     return .unresolvedFilename(value)
            case .unresolvedRelativePath: return .unresolvedRelativePath(value)
            }
        }
    }
}

final class HistoryManager {
    static let shared = HistoryManager()
    static let didChange = Notification.Name("HistoryManager.didChange")

    private(set) var records: [HistoryRecord] = []
    private let maxRecords = 200
    private let ioQueue = DispatchQueue(label: "Glance.HistoryManager.io")

    private init() {
        load()
    }

    func record(selectedText: String, detectedPaths: [DetectedPath]) {
        // Only persist items that resolved to a real URL. Unresolved bare
        // filename / relative-path tokens are dropped — they're not useful as
        // history entries once their lookup attempt is over.
        let items = detectedPaths
            .filter { $0.url != nil }
            .compactMap { HistoryRecord.Item.from($0) }
        guard !items.isEmpty else { return }
        let record = HistoryRecord(timestamp: Date(),
                                    selectedText: selectedText,
                                    items: items)
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records.removeLast(records.count - maxRecords)
        }
        save()
        NotificationCenter.default.post(name: HistoryManager.didChange, object: self)
    }

    func clear() {
        records.removeAll()
        save()
        NotificationCenter.default.post(name: HistoryManager.didChange, object: self)
    }

    // MARK: - Persistence

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
            .appendingPathComponent("Glance", isDirectory: true)
        try? FileManager.default.createDirectory(at: base,
                                                  withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([HistoryRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func save() {
        let snapshot = records
        let url = storeURL
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
