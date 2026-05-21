import AppKit
import Foundation

final class FileNameResolver {

    struct Match {
        let url: URL
        let lastModified: Date?
        let isInUserHome: Bool
    }

    private let quickSearchMaxDirectories = 20_000
    private let quickSearchTimeBudget: TimeInterval = 0.50
    private let quickSearchMaxDepth = 10

    private let deepSearchMaxDirectories = 50_000
    private let deepSearchTimeBudget: TimeInterval = 1.0
    private let deepSearchMaxDepth = 12

    private let mdfindTimeout: TimeInterval = 0.8

    private let blocklistSubstrings: [String] = [
        "/.Trash/", "/.Trashes/", "/Trash/",
        "/Library/Caches/",
        "/private/var/folders/", "/.git/", ".icloud"
    ]

    private let preferredAncestors: [String] = [
        NSHomeDirectory() + "/Desktop",
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents",
    ]

    private let quickSearchBaseNames = ["Desktop", "Documents", "Downloads"]

    private let skippedDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", "DerivedData", "build", "dist",
        ".build", ".dart_tool", ".next", ".nuxt", ".cache", "Pods", "Carthage",
        "Library", "Applications", "Movies", "Music", "Pictures"
    ]

    private var activeResolutions: [ActiveResolution] = []
    private let resolutionLock = NSLock()

    private struct ActiveResolution {
        let id = UUID()
        let completion: ([Match]) -> Void
        let normalizedToken: String
    }

    func resolve(token: String,
                 timeout: TimeInterval = 1.5,
                 limit: Int = 24,
                 completion: @escaping ([Match]) -> Void) {
        let normalizedToken = normalizeToken(token)
        guard !normalizedToken.isEmpty else {
            completion([])
            return
        }

        if let cachedURL = FilenameCache.shared.lookup(token: normalizedToken) {
            Logger.info("FileNameResolver: cache hit for '\(token)'")
            completion([Match(url: cachedURL, lastModified: nil,
                              isInUserHome: cachedURL.path.hasPrefix(NSHomeDirectory()))])
            return
        }

        let quickMatches = quickFilesystemMatches(token: normalizedToken, limit: limit)
        if !quickMatches.isEmpty {
            if let best = quickMatches.first {
                FilenameCache.shared.store(token: normalizedToken, url: best.url)
            }
            Logger.info("FileNameResolver: quick hit for '\(token)' -> \(quickMatches.count)")
            completion(quickMatches)
            return
        }

        let resolution = ActiveResolution(
            completion: completion,
            normalizedToken: normalizedToken
        )
        resolutionLock.lock()
        activeResolutions.append(resolution)
        resolutionLock.unlock()

        let group = DispatchGroup()
        let resultLock = NSLock()
        var allMatches: [Match] = []
        var seenPaths = Set<String>()

        func addMatches(_ matches: [Match]) {
            resultLock.lock()
            for match in matches {
                let path = match.url.path
                if seenPaths.insert(path).inserted {
                    allMatches.append(match)
                }
            }
            resultLock.unlock()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { group.leave() }
            guard let self = self else { return }
            addMatches(self.mdfindExact(basename: (normalizedToken as NSString).lastPathComponent,
                                         limit: limit))
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { group.leave() }
            guard let self = self else { return }
            addMatches(self.mdfindFuzzy(basename: (normalizedToken as NSString).lastPathComponent,
                                         limit: limit))
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { group.leave() }
            guard let self = self else { return }
            addMatches(self.deepFilesystemSearch(token: normalizedToken, limit: limit))
        }

        let timeoutWork = DispatchWorkItem { [weak self] in
            self?.finishResolution(id: resolution.id, matches: allMatches, limit: limit,
                                   reason: "timeout", token: normalizedToken)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        group.notify(queue: .main) { [weak self] in
            timeoutWork.cancel()
            self?.finishResolution(id: resolution.id, matches: allMatches, limit: limit,
                                   reason: "completed", token: normalizedToken)
        }
    }

    func cancelAll() {
        resolutionLock.lock()
        let current = activeResolutions
        activeResolutions.removeAll()
        resolutionLock.unlock()
        for resolution in current {
            DispatchQueue.main.async { resolution.completion([]) }
        }
    }

    private func finishResolution(id: UUID, matches: [Match], limit: Int,
                                  reason: String, token: String) {
        resolutionLock.lock()
        guard let idx = activeResolutions.firstIndex(where: { $0.id == id }) else {
            resolutionLock.unlock()
            return
        }
        let resolution = activeResolutions[idx]
        activeResolutions.remove(at: idx)
        resolutionLock.unlock()

        let sorted = deduplicateAndSort(matches: matches, limit: limit)
        Logger.info("FileNameResolver: '\(token)' -> \(sorted.count) [\(reason)]")

        if let best = sorted.first {
            FilenameCache.shared.store(token: token, url: best.url)
        }
        resolution.completion(sorted)
    }

    private func mdfindExact(basename: String, limit: Int) -> [Match] {
        guard !basename.isEmpty else { return [] }
        let home = NSHomeDirectory()
        let output = runMdfind(arguments: ["-name", basename, "-onlyin", home])
        return parseMdfindOutput(output, limit: limit)
    }

    private func mdfindFuzzy(basename: String, limit: Int) -> [Match] {
        guard !basename.isEmpty else { return [] }
        let home = NSHomeDirectory()
        let escaped = basename.replacingOccurrences(of: "\"", with: "\\\"")
        let predicate = "kMDItemFSName == \"\(escaped)\"cd"
        let output = runMdfind(arguments: [predicate, "-onlyin", home])
        return parseMdfindOutput(output, limit: limit)
    }

    private func runMdfind(arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            Logger.info("FileNameResolver: mdfind failed to start: \(error)")
            return nil
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + mdfindTimeout)
        timer.setEventHandler { [weak task] in
            task?.terminate()
        }
        timer.resume()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        timer.cancel()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            Logger.info("FileNameResolver: mdfind exited with status \(task.terminationStatus)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func parseMdfindOutput(_ output: String?, limit: Int) -> [Match] {
        guard let output = output, !output.isEmpty else { return [] }
        let home = NSHomeDirectory()
        let paths = output.components(separatedBy: .newlines).filter { !$0.isEmpty }.prefix(limit)

        var matches: [Match] = []
        for path in paths {
            if blocklistSubstrings.contains(where: { path.contains($0) }) { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            matches.append(Match(
                url: url,
                lastModified: values?.contentModificationDate,
                isInUserHome: path.hasPrefix(home + "/") || path == home
            ))
        }
        return matches
    }

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

        for url in directCandidateURLs(for: token) { append(url) }
        if matches.count >= limit { return sortedMatches(matches, limit: limit) }

        let started = Date()
        var visitedDirectories = 0
        for root in quickSearchRoots() {
            guard Date().timeIntervalSince(started) < quickSearchTimeBudget else { break }
            searchDirectory(
                root: root, basename: basename, suffix: suffix,
                maxDepth: quickSearchMaxDepth, limit: limit,
                started: started, visitedDirectories: &visitedDirectories,
                seen: &seen, matches: &matches
            )
            if matches.count >= limit || visitedDirectories >= quickSearchMaxDirectories { break }
        }
        return sortedMatches(matches, limit: limit)
    }

    private func deepFilesystemSearch(token: String, limit: Int) -> [Match] {
        let basename = (token as NSString).lastPathComponent
        guard !basename.isEmpty else { return [] }

        let suffix = token.contains("/") ? "/" + token.lowercased() : nil
        var matches: [Match] = []
        var seen = Set<String>()

        let started = Date()
        var visitedDirectories = 0
        for root in deepSearchRoots() {
            guard Date().timeIntervalSince(started) < deepSearchTimeBudget else { break }
            searchDirectory(
                root: root, basename: basename, suffix: suffix,
                maxDepth: deepSearchMaxDepth, limit: limit,
                started: started, visitedDirectories: &visitedDirectories,
                seen: &seen, matches: &matches
            )
            if matches.count >= limit || visitedDirectories >= deepSearchMaxDirectories { break }
        }
        return sortedMatches(matches, limit: limit)
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

    private func deepSearchRoots() -> [URL] {
        let homePath = NSHomeDirectory()
        var roots: [URL] = []

        let projectDirs = ["Projects", "Workspace", "Code", "Dev", "work"]
        for dir in projectDirs {
            let url = URL(fileURLWithPath: homePath).appendingPathComponent(dir, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { roots.append(url) }
        }
        roots.append(contentsOf: commonRoots())
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
                    at: dir, includingPropertiesForKeys: keys,
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
                if depth + 1 < maxDepth { queue.append((child, depth + 1)) }
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
              visitedDirectories < deepSearchMaxDirectories,
              Date().timeIntervalSince(started) < deepSearchTimeBudget {
            let (dir, depth) = queue.removeFirst()
            visitedDirectories += 1
            guard let children = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys,
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
        return Match(url: canonical,
                     lastModified: values?.contentModificationDate,
                     isInUserHome: path.hasPrefix(home + "/") || path == home)
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

    private func deduplicateAndSort(matches: [Match], limit: Int) -> [Match] {
        var seen = Set<String>()
        var unique: [Match] = []
        for match in matches {
            if seen.insert(match.url.path).inserted { unique.append(match) }
        }
        return sortedMatches(unique, limit: limit)
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

    private func isUnderPreferred(_ path: String) -> Bool {
        preferredAncestors.contains { path.hasPrefix($0 + "/") }
    }

    private func normalizeToken(_ token: String) -> String {
        var value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        while let last = value.last, ",.;!?\"')]}".contains(last) { value.removeLast() }
        while value.hasPrefix("./") { value.removeFirst(2) }
        return value
    }
}
