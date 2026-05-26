import Foundation

struct CacheEntry: Codable {
    let url: String
    let timestamp: Date
}

/// Lightweight LRU cache for token → absolute-path lookups.
///
/// FileNameResolver hits this before launching a Spotlight query. On a
/// cache hit the result is returned instantly; on a miss the normal
/// Spotlight / filesystem-fallback pipeline runs and the best match is
/// written back for next time.
///
/// Backed by a JSON file in Application Support so the cache survives
/// app restarts.
final class FilenameCache {
    static let shared = FilenameCache()

    private var entries: [String: CacheEntry] = [:]
    private let maxEntries = 500
    private let ioQueue = DispatchQueue(label: "Glance.FilenameCache.io")

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
            .appendingPathComponent("Glance", isDirectory: true)
        try? FileManager.default.createDirectory(at: base,
                                                  withIntermediateDirectories: true)
        return base.appendingPathComponent("filename-cache.json")
    }

    private init() {
        load()
    }

    // MARK: - Public API

    /// Look up a token. On hit the entry's timestamp is refreshed
    /// so it ranks as most-recently-used.
    func lookup(token: String) -> URL? {
        guard var entry = entries[token] else { return nil }
        let url = URL(fileURLWithPath: entry.url)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            entries.removeValue(forKey: token)
            save()
            return nil
        }
        entry = CacheEntry(url: entry.url, timestamp: Date())
        entries[token] = entry
        return url
    }

    /// Store a successful resolution.  Triggers an async disk write and
    /// evicts the oldest entry if the cache has grown past `maxEntries`.
    func store(token: String, url: URL) {
        let path = url.path
        entries[token] = CacheEntry(url: path, timestamp: Date())
        evictIfNeeded()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([String: CacheEntry].self, from: data) else {
            // Corrupt cache — wipe and start fresh so we don't block lookups.
            try? FileManager.default.removeItem(at: storeURL)
            return
        }
        entries = decoded
    }

    private func save() {
        let snapshot = entries
        let url = storeURL
        ioQueue.async {
            let formatter = ISO8601DateFormatter()
            var json: [String: [String: String]] = [:]
            for (token, entry) in snapshot {
                json[token] = [
                    "url": entry.url,
                    "timestamp": formatter.string(from: entry.timestamp)
                ]
            }
            guard JSONSerialization.isValidJSONObject(json),
                  let data = try? JSONSerialization.data(
                    withJSONObject: json,
                    options: [.prettyPrinted, .sortedKeys]
                  ) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Eviction

    private func evictIfNeeded() {
        guard entries.count > maxEntries else { return }
        let sorted = entries.sorted { $0.value.timestamp < $1.value.timestamp }
        let toRemove = sorted.prefix(entries.count - maxEntries).map { $0.key }
        for key in toRemove {
            entries.removeValue(forKey: key)
        }
    }
}
