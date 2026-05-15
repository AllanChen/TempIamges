import AppKit
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
        /// For relative-path tokens (`xporn/README.md`) we only ask Spotlight
        /// for the basename and then filter the results in Swift to those
        /// whose path ends with `/xporn/README.md`. This is more reliable
        /// than a compound `kMDItemPath LIKE` predicate.
        let pathSuffix: String?
        var hasCompleted = false
        var didTryFullDisk = false
        var timeoutWork: DispatchWorkItem?
        let completion: ([Match]) -> Void

        init(token: String, query: NSMetadataQuery, pathSuffix: String?,
             completion: @escaping ([Match]) -> Void) {
            self.token = token
            self.query = query
            self.pathSuffix = pathSuffix
            self.completion = completion
        }
    }

    private var jobs: [Job] = []

    // Substrings whose presence in a URL path disqualifies a match.
    // Trash variants covered:
    //   /.Trash/        — user home trash, e.g. /Users/lily/.Trash/...
    //   /.Trashes/      — per-volume trash, e.g. /Volumes/Backup/.Trashes/501/...
    //   /Trash/         — bare "Trash" folder name (rare but covers ad-hoc cases)
    private let blocklistSubstrings: [String] = [
        "/.Trash/", "/.Trashes/", "/Trash/",
        "/Library/Caches/",
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
        // Bare filenames (no path separator) are cached after the first
        // successful resolution so repeated lookups bypass Spotlight.
        if !token.contains("/"), let cachedURL = FilenameCache.shared.lookup(token: token) {
            Logger.info("FileNameResolver: cache hit for '\(token)' → \(cachedURL.path)")
            let match = Match(url: cachedURL,
                              lastModified: nil,
                              isInUserHome: cachedURL.path.hasPrefix(NSHomeDirectory()))
            completion([match])
            return
        }

        let basename = (token as NSString).lastPathComponent
        let pathSuffix: String? = token.contains("/") ? "/" + token : nil

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: "kMDItemFSName ==[c] %@", basename)
        query.sortDescriptors = [
            NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey,
                             ascending: false)
        ]

        let job = Job(token: token, query: query,
                      pathSuffix: pathSuffix, completion: completion)

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
        let matches = self.processItems(items, suffix: job.pathSuffix, limit: limit)

        // Diagnostic: show what Spotlight returned (raw count, sample paths,
        // and how many survived filtering). Helps debug "file exists but not
        // found" reports.
        let phase = job.didTryFullDisk ? 2 : 1
        let samplePaths = items.prefix(3).compactMap {
            $0.value(forAttribute: NSMetadataItemPathKey) as? String
        }
        Logger.info("FileNameResolver: '\(job.token)' phase=\(phase) raw=\(items.count) kept=\(matches.count) sample=\(samplePaths)")

        // Two-phase: if home scope was empty, retry with whole-local-disk.
        if matches.isEmpty && !job.didTryFullDisk {
            job.didTryFullDisk = true
            job.query.searchScopes = [NSMetadataQueryLocalComputerScope]
            _ = job.query.start()
            return
        }

        // Both Spotlight phases empty — try a filesystem walk of common
        // user directories as a last resort. Handles recently created /
        // not-yet-indexed files.
        if matches.isEmpty {
            let basename = (job.token as NSString).lastPathComponent
            let suffix = job.pathSuffix
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let fsMatches = self?.fallbackFilesystemSearch(
                    basename: basename, suffix: suffix, limit: limit
                ) ?? []
                DispatchQueue.main.async {
                    self?.finish(job: job, with: fsMatches, reason: "fs-fallback")
                }
            }
            return
        }

        finish(job: job, with: matches, reason: "gathered")
    }

    /// Walks a small set of well-known user directories looking for a file
    /// with the given basename. Used when Spotlight can't / hasn't indexed
    /// the file yet. Bounded by `limit`; skips hidden + package contents.
    ///
    /// On macOS Mojave+ each of ~/Desktop, ~/Documents, ~/Downloads has its
    /// own TCC entry, so naïve enumeration causes multiple permission
    /// prompts. To consolidate, we gate the walk behind a single Full Disk
    /// Access ask. Until FDA is granted (or the user explicitly declines),
    /// the walk silently returns empty.
    private func fallbackFilesystemSearch(basename: String,
                                          suffix: String?,
                                          limit: Int) -> [Match] {
        guard Self.ensureFullDiskAccess() else {
            Logger.info("FileNameResolver: fs-fallback skipped — Full Disk Access not granted")
            return []
        }

        let home = NSHomeDirectory()
        let candidateRoots = [
            home + "/Desktop",
            home + "/Documents",
            home + "/Downloads",
        ]
        let fm = FileManager.default
        let roots = candidateRoots.filter { fm.fileExists(atPath: $0) }

        let targetName = basename.lowercased()
        let targetSuffix = suffix?.lowercased()
        var results: [Match] = []

        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]

        outer: for root in roots {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if url.lastPathComponent.lowercased() != targetName { continue }
                if let s = targetSuffix,
                   !url.path.lowercased().hasSuffix(s) { continue }

                let canonical = url.resolvingSymlinksInPath()
                let attrs = try? canonical.resourceValues(forKeys: Set(resourceKeys))
                if attrs?.isDirectory == true { continue }
                results.append(Match(
                    url: canonical,
                    lastModified: attrs?.contentModificationDate,
                    isInUserHome: true
                ))
                if results.count >= limit { break outer }
            }
        }

        Logger.info("FileNameResolver: '\(basename)' fs-fallback found \(results.count)")
        return results
    }

    private func finish(job: Job, limit: Int, reason: String) {
        let items = (0..<job.query.resultCount).compactMap {
            job.query.result(at: $0) as? NSMetadataItem
        }
        let matches = self.processItems(items, suffix: job.pathSuffix, limit: limit)
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

        // Cache the best match for bare filenames so the next lookup is instant.
        if let best = matches.first, !job.token.contains("/") {
            FilenameCache.shared.store(token: job.token, url: best.url)
        }

        DispatchQueue.main.async { job.completion(matches) }
    }

    private func processItems(_ items: [NSMetadataItem], suffix: String?, limit: Int) -> [Match] {
        let home = NSHomeDirectory()
        var seen = Set<String>()
        var result: [Match] = []

        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !path.isEmpty else { continue }

            // Relative-path filter: keep only paths ending with `/<token>`
            // (case-insensitive — Spotlight is case-insensitive anyway).
            if let suffix = suffix,
               path.lowercased().hasSuffix(suffix.lowercased()) == false {
                continue
            }

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

    // MARK: - Full Disk Access gate

    private static let fdaPromptShownKey = "com.glance.fdaPromptShown"

    /// Returns true when FDA is currently granted. Otherwise shows a single
    /// consolidated NSAlert (only the first time per install) directing the
    /// user to System Settings, then returns false.
    static func ensureFullDiskAccess() -> Bool {
        if hasFullDiskAccess() {
            // Previously prompted? Clear the flag so a future revocation /
            // re-grant cycle works cleanly.
            UserDefaults.standard.removeObject(forKey: fdaPromptShownKey)
            return true
        }
        if UserDefaults.standard.bool(forKey: fdaPromptShownKey) {
            return false  // already asked, user opted out
        }
        UserDefaults.standard.set(true, forKey: fdaPromptShownKey)
        DispatchQueue.main.async { presentFDAAlert() }
        return false
    }

    /// FDA detection by trying to read a TCC-protected system file. If it's
    /// readable, FDA must be on.
    private static func hasFullDiskAccess() -> Bool {
        FileManager.default.isReadableFile(
            atPath: "/Library/Application Support/com.apple.TCC/TCC.db"
        )
    }

    private static func presentFDAAlert() {
        let alert = NSAlert()
        alert.messageText = "Allow Glance to access your files"
        alert.informativeText = """
        To find files Spotlight hasn't indexed yet, Glance needs Full \
        Disk Access. Granting it here means we won't ask again for each \
        folder (Documents, Desktop, Downloads).

        Click "Open Settings" to enable it in System Settings → Privacy & \
        Security → Full Disk Access, then toggle Glance (or \
        Glance) on. You may need to restart the app for it to \
        take effect.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
