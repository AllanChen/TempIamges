import AppKit
import Foundation

/// Resolves bare filenames / relative paths to absolute URLs.
///
/// Resolution order:
///   1. Cache + direct filesystem checks around likely project roots.
///   2. `NSMetadataQueryUserHomeScope`.
///   3. If phase 2 returns 0 results, retry with `NSMetadataQueryLocalComputerScope`.
///   4. FDA-gated filesystem fallback for common user folders.
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
    private let quickSearchBaseNames = ["Desktop", "Documents", "Downloads"]
    private let quickSearchMaxDirectories = 12_000
    private let quickSearchTimeBudget: TimeInterval = 0.35
    private let quickSearchMaxDepth = 7
    private let skippedDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", "DerivedData", "build", "dist",
        ".build", ".dart_tool", ".next", ".nuxt", ".cache", "Pods", "Carthage",
        "Library", "Applications", "Movies", "Music", "Pictures"
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
        let normalizedToken = normalizeToken(token)
        guard !normalizedToken.isEmpty else {
            completion([])
            return
        }

        if let cachedURL = FilenameCache.shared.lookup(token: normalizedToken) {
            Logger.info("FileNameResolver: cache hit for '\(token)' → \(cachedURL.path)")
            let match = Match(url: cachedURL,
                              lastModified: nil,
                              isInUserHome: cachedURL.path.hasPrefix(NSHomeDirectory()))
            completion([match])
            return
        }

        let quickMatches = quickFilesystemMatches(token: normalizedToken, limit: limit)
        if !quickMatches.isEmpty {
            if let best = quickMatches.first {
                FilenameCache.shared.store(token: normalizedToken, url: best.url)
            }
            Logger.info("FileNameResolver: quick hit for '\(token)' → \(quickMatches.count) match(es)")
            completion(quickMatches)
            return
        }

        let basename = (normalizedToken as NSString).lastPathComponent
        let pathSuffix: String? = normalizedToken.contains("/") ? "/" + normalizedToken : nil

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: "kMDItemFSName ==[c] %@", basename)
        query.sortDescriptors = [
            NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey,
                             ascending: false)
        ]

        let job = Job(token: normalizedToken, query: query,
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

        // Cache the best match so the next lookup is instant. Cache lookup
        // verifies the file still exists before returning it.
        if let best = matches.first {
            FilenameCache.shared.store(token: job.token, url: best.url)
        }

        DispatchQueue.main.async { job.completion(matches) }
    }

    // MARK: - Fast local search

    /// Cheap path resolution before Spotlight. This handles the common case
    /// where the user gives a project-relative path such as
    /// `Glance/Sources/PreviewPanel.swift`.
    private func quickFilesystemMatches(token: String, limit: Int) -> [Match] {
        let basename = (token as NSString).lastPathComponent
        guard !basename.isEmpty else { return [] }

        let suffix = token.contains("/") ? "/" + token.lowercased() : nil
        var matches: [Match] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            guard matches.count < limit,
                  let match = makeMatch(url: url),
                  matchesSuffix(match.url.path, suffix: suffix),
                  seen.insert(match.url.path).inserted else { return }
            matches.append(match)
        }

        for url in directCandidateURLs(for: token) {
            append(url)
        }
        if matches.count >= limit {
            return sortedMatches(matches, limit: limit)
        }

        let started = Date()
        var visitedDirectories = 0
        for root in quickSearchRoots() {
            guard Date().timeIntervalSince(started) < quickSearchTimeBudget else { break }
            searchDirectory(
                root: root,
                basename: basename,
                suffix: suffix,
                maxDepth: quickSearchMaxDepth,
                limit: limit,
                started: started,
                visitedDirectories: &visitedDirectories,
                seen: &seen,
                matches: &matches
            )
            if matches.count >= limit || visitedDirectories >= quickSearchMaxDirectories {
                break
            }
        }

        return sortedMatches(matches, limit: limit)
    }

    private func directCandidateURLs(for token: String) -> [URL] {
        var candidates: [URL] = []

        if token.lowercased().hasPrefix("file://"), let url = URL(string: token) {
            candidates.append(url)
        } else if token.hasPrefix("~/") {
            candidates.append(URL(fileURLWithPath: (token as NSString).expandingTildeInPath))
        } else if token.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: token))
        } else {
            for root in relativeCandidateRoots() {
                candidates.append(appendingRelativePath(token, to: root))
            }
        }

        return candidates
    }

    private func relativeCandidateRoots() -> [URL] {
        var roots = orderedUnique(commonRoots())
        let expandableRoots = commonRoots().filter { url in
            quickSearchBaseNames.contains(url.lastPathComponent)
                || url.path == FileManager.default.currentDirectoryPath
        }
        for root in expandableRoots {
            roots.append(contentsOf: shallowDirectories(under: root, maxDepth: 2, limit: 500))
        }
        return orderedUnique(roots)
    }

    private func quickSearchRoots() -> [URL] {
        let homePath = NSHomeDirectory()
        var roots: [URL] = []
        roots.append(contentsOf: commonRoots().filter { $0.path != homePath })
        for root in commonRoots() where quickSearchBaseNames.contains(root.lastPathComponent) {
            roots.append(contentsOf: shallowDirectories(under: root, maxDepth: 1, limit: 200))
        }
        roots.append(URL(fileURLWithPath: homePath, isDirectory: true))
        return orderedUnique(roots)
    }

    private func commonRoots() -> [URL] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        var roots: [URL] = []

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true).standardizedFileURL
        if cwd.path != "/" {
            roots.append(cwd)
            var parent = cwd.deletingLastPathComponent()
            while parent.path != "/" && parent.path.hasPrefix(home.path) {
                roots.append(parent)
                if parent.path == home.path { break }
                parent = parent.deletingLastPathComponent()
            }
        }

        roots.append(home)
        for name in quickSearchBaseNames {
            roots.append(home.appendingPathComponent(name, isDirectory: true))
        }
        return orderedUnique(roots).filter { isSearchableDirectory($0) }
    }

    private func shallowDirectories(under root: URL, maxDepth: Int, limit: Int) -> [URL] {
        guard maxDepth > 0 else { return [] }
        var result: [URL] = []
        var queue: [(URL, Int)] = [(root, 0)]
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]

        while !queue.isEmpty && result.count < limit {
            let (dir, depth) = queue.removeFirst()
            guard depth < maxDepth,
                  let children = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else { continue }

            let dirs = children.compactMap { child -> (URL, Date)? in
                guard isSearchableDirectory(child),
                      let values = try? child.resourceValues(forKeys: Set(keys)),
                      values.isDirectory == true,
                      values.isPackage != true else { return nil }
                return (child, values.contentModificationDate ?? .distantPast)
            }.sorted { $0.1 > $1.1 }

            for (child, _) in dirs {
                result.append(child)
                if depth + 1 < maxDepth {
                    queue.append((child, depth + 1))
                }
                if result.count >= limit { break }
            }
        }

        return result
    }

    private func searchDirectory(root: URL,
                                 basename: String,
                                 suffix: String?,
                                 maxDepth: Int,
                                 limit: Int,
                                 started: Date,
                                 visitedDirectories: inout Int,
                                 seen: inout Set<String>,
                                 matches: inout [Match]) {
        var queue: [(URL, Int)] = [(root, 0)]
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]

        while !queue.isEmpty,
              matches.count < limit,
              visitedDirectories < quickSearchMaxDirectories,
              Date().timeIntervalSince(started) < quickSearchTimeBudget {
            let (dir, depth) = queue.removeFirst()
            visitedDirectories += 1
            guard let children = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            var childDirs: [(URL, Date)] = []
            for child in children {
                let values = try? child.resourceValues(forKeys: Set(keys))
                if child.lastPathComponent.compare(basename, options: [.caseInsensitive]) == .orderedSame,
                   values?.isDirectory != true,
                   let match = makeMatch(url: child),
                   matchesSuffix(match.url.path, suffix: suffix),
                   seen.insert(match.url.path).inserted {
                    matches.append(match)
                    if matches.count >= limit { break }
                }

                guard depth < maxDepth,
                      values?.isDirectory == true,
                      values?.isPackage != true,
                      isSearchableDirectory(child) else { continue }
                childDirs.append((child, values?.contentModificationDate ?? .distantPast))
            }

            childDirs.sort { $0.1 > $1.1 }
            queue.append(contentsOf: childDirs.map { ($0.0, depth + 1) })
        }
    }

    private func makeMatch(url: URL) -> Match? {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = canonical.path
        if blocklistSubstrings.contains(where: { path.contains($0) }) { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }

        let values = try? canonical.resourceValues(forKeys: [.contentModificationDateKey])
        let home = NSHomeDirectory()
        return Match(
            url: canonical,
            lastModified: values?.contentModificationDate,
            isInUserHome: path.hasPrefix(home + "/") || path == home
        )
    }

    private func sortedMatches(_ matches: [Match], limit: Int) -> [Match] {
        let sorted = matches.sorted { a, b in
            let aPref = isUnderPreferred(a.url.path)
            let bPref = isUnderPreferred(b.url.path)
            if aPref != bPref { return aPref && !bPref }
            if a.isInUserHome != b.isInUserHome { return a.isInUserHome && !b.isInUserHome }
            switch (a.lastModified, b.lastModified) {
            case let (la?, lb?): return la > lb
            case (_?, nil):       return true
            case (nil, _?):       return false
            default:              return a.url.path.count < b.url.path.count
            }
        }
        return Array(sorted.prefix(limit))
    }

    private func matchesSuffix(_ path: String, suffix: String?) -> Bool {
        guard let suffix else { return true }
        return path.lowercased().hasSuffix(suffix)
    }

    private func appendingRelativePath(_ token: String, to root: URL) -> URL {
        URL(fileURLWithPath: (root.path as NSString).appendingPathComponent(token)).standardizedFileURL
    }

    private func isSearchableDirectory(_ url: URL) -> Bool {
        !skippedDirectoryNames.contains(url.lastPathComponent)
    }

    private func orderedUnique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                result.append(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        return result
    }

    private func normalizeToken(_ token: String) -> String {
        var value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        while let last = value.last, ",.;!?\"')]}".contains(last) {
            value.removeLast()
        }
        while value.hasPrefix("./") {
            value.removeFirst(2)
        }
        return value
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
        alert.messageText = "Allow Glance to access your files".localized
        alert.informativeText = NSLocalizedString("fda_alert_body", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings".localized)
        alert.addButton(withTitle: "Not Now".localized)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
