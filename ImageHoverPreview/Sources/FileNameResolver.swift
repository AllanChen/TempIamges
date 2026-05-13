import Foundation

/// Resolves bare filenames / relative paths to absolute URLs via Spotlight.
///
/// Two-phase scope:
///   1. `NSMetadataQueryUserHomeScope` — fast (~50–150 ms on a warm cache).
///   2. If phase 1 returns 0 results, retry with `NSMetadataQueryLocalComputerScope`.
///
/// Cancels in-flight queries on hotkey release. Completion always fires
/// exactly once, on the main queue.
final class FileNameResolver {

    struct Match {
        let url: URL
        let lastModified: Date?
        let isInUserHome: Bool
    }

    private final class Job {
        let token: String
        let query: NSMetadataQuery
        var hasCompleted = false
        var didTryFullDisk = false
        var timeoutWork: DispatchWorkItem?
        let completion: ([Match]) -> Void

        init(token: String, query: NSMetadataQuery,
             completion: @escaping ([Match]) -> Void) {
            self.token = token
            self.query = query
            self.completion = completion
        }
    }

    private var jobs: [Job] = []

    // Substrings whose presence in a URL path disqualifies a match.
    private let blocklistSubstrings: [String] = [
        "/.Trash/", "/Library/Caches/",
        "/private/var/folders/", "/.git/", ".icloud"
    ]

    // Directories whose direct descendants get sorted to the front.
    private let preferredAncestors: [String] = [
        NSHomeDirectory() + "/Desktop",
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents",
    ]

    /// Resolve a filename or relative path. Completion fires once, on .main.
    /// - parameter token: e.g. `"screenshot.png"` or `"assets/foo.png"`.
    /// - parameter timeout: hard deadline; on expiry, completes with whatever
    ///   was gathered (possibly empty).
    /// - parameter limit: caller-imposed cap on returned matches.
    func resolve(token: String,
                 timeout: TimeInterval = 1.2,
                 limit: Int = 24,
                 completion: @escaping ([Match]) -> Void) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = predicate(for: token)
        query.sortDescriptors = [
            NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey,
                             ascending: false)
        ]

        let job = Job(token: token, query: query, completion: completion)

        let timeoutWork = DispatchWorkItem { [weak self] in
            self?.finish(job: job, limit: limit, reason: "timeout")
        }
        job.timeoutWork = timeoutWork

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.handleGatheringFinished(job: job, limit: limit)
        }

        jobs.append(job)

        let started = query.start()
        if !started {
            // Spotlight unavailable — degrade silently.
            finish(job: job, limit: limit, reason: "start failed")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
    }

    /// Cancel every in-flight resolution (called when the preview is dismissed
    /// or a new resolution starts). Completions for cancelled jobs fire with
    /// an empty array.
    func cancelAll() {
        let current = jobs
        jobs.removeAll()
        for job in current {
            guard !job.hasCompleted else { continue }
            job.hasCompleted = true
            job.timeoutWork?.cancel()
            job.query.stop()
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering,
                                                       object: job.query)
            DispatchQueue.main.async { job.completion([]) }
        }
    }

    // MARK: - Internals

    private func handleGatheringFinished(job: Job, limit: Int) {
        job.query.stop()
        let items = (0..<job.query.resultCount).compactMap {
            job.query.result(at: $0) as? NSMetadataItem
        }
        let matches = self.processItems(items, limit: limit)

        // Two-phase: if home scope was empty, retry with whole-local-disk.
        if matches.isEmpty && !job.didTryFullDisk {
            job.didTryFullDisk = true
            job.query.searchScopes = [NSMetadataQueryLocalComputerScope]
            _ = job.query.start()
            return
        }

        finish(job: job, with: matches, reason: "gathered")
    }

    private func finish(job: Job, limit: Int, reason: String) {
        let items = (0..<job.query.resultCount).compactMap {
            job.query.result(at: $0) as? NSMetadataItem
        }
        let matches = self.processItems(items, limit: limit)
        finish(job: job, with: matches, reason: reason)
    }

    private func finish(job: Job, with matches: [Match], reason: String) {
        guard !job.hasCompleted else { return }
        job.hasCompleted = true
        job.timeoutWork?.cancel()
        job.query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering,
                                                   object: job.query)
        jobs.removeAll { $0 === job }
        Logger.info("FileNameResolver: '\(job.token)' → \(matches.count) match(es) [\(reason)]")
        DispatchQueue.main.async { job.completion(matches) }
    }

    private func processItems(_ items: [NSMetadataItem], limit: Int) -> [Match] {
        let home = NSHomeDirectory()
        var seen = Set<String>()
        var result: [Match] = []

        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !path.isEmpty else { continue }

            if blocklistSubstrings.contains(where: { path.contains($0) }) { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let canonical = url.path
            if !seen.insert(canonical).inserted { continue }

            let mtime = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let inHome = canonical.hasPrefix(home + "/") || canonical == home
            result.append(Match(url: url, lastModified: mtime, isInUserHome: inHome))
        }

        result.sort { (a, b) in
            // Tier 1: prefer items under Desktop / Downloads / Documents.
            let aPref = isUnderPreferred(a.url.path)
            let bPref = isUnderPreferred(b.url.path)
            if aPref != bPref { return aPref && !bPref }
            // Tier 2: prefer items anywhere under the user's home.
            if a.isInUserHome != b.isInUserHome { return a.isInUserHome && !b.isInUserHome }
            // Tier 3: most recently modified first.
            switch (a.lastModified, b.lastModified) {
            case let (la?, lb?): return la > lb
            case (_?, nil):       return true
            case (nil, _?):       return false
            default:              return false
            }
        }
        return Array(result.prefix(limit))
    }

    private func isUnderPreferred(_ path: String) -> Bool {
        preferredAncestors.contains { path.hasPrefix($0 + "/") }
    }

    private func predicate(for token: String) -> NSPredicate {
        // Relative path with internal slashes → match the basename AND require
        // the path to end with the user's suffix (case-insensitive).
        if token.contains("/") {
            let basename = (token as NSString).lastPathComponent
            // LIKE wildcard: leading "*/" lets Spotlight match any parent
            // directory, suffix is the user's relative path exactly.
            let suffix = "*/" + token
            return NSPredicate(
                format: "kMDItemFSName ==[c] %@ AND kMDItemPath LIKE[c] %@",
                basename, suffix
            )
        }
        return NSPredicate(format: "kMDItemFSName ==[c] %@", token)
    }
}
