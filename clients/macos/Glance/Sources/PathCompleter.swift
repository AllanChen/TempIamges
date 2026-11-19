import Foundation

/// Finishes a cut-off path the way a shell's Tab key does. A selection that
/// stops before the end of a name (`~/Downloads/Glance/kyoto-da`), before its
/// extension (`shots/hero.pn`), or in the middle of a folder name
/// (`~/Desk/hero.png`) still names one file on disk — this finds it.
enum PathCompleter {
    /// Most files one completion may return; broader prefixes keep the newest.
    static let limit = 12
    /// Folders larger than this are not scanned; the prefix is too ambiguous there.
    private static let maxEntries = 20_000
    /// At most this many sibling folders are followed when a folder name is cut off.
    private static let maxFolderBranches = 6

    /// `token` is a path fragment (absolute, home-rooted or relative). Relative
    /// fragments are tried under each root in order. `accepts` decides which
    /// files count (by extension). Returns files, most relevant first.
    static func complete(_ rawToken: String, roots: [URL], accepts: (String) -> Bool) -> [URL] {
        var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = token.last, ",;:!?\"'`)]}>".contains(last) { token.removeLast() }
        guard !token.isEmpty, !token.hasSuffix("/"), !token.contains("..") else { return [] }

        var bases: [URL]
        var remainder = token
        if token.hasPrefix("~/") {
            bases = [URL(fileURLWithPath: UserHome.path, isDirectory: true)]
            remainder = String(token.dropFirst(2))
        } else if token.hasPrefix("/") {
            bases = [URL(fileURLWithPath: "/", isDirectory: true)]
            remainder = String(token.dropFirst())
        } else {
            while remainder.hasPrefix("./") { remainder.removeFirst(2) }
            bases = roots
        }
        let components = remainder.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let last = components.last, last.count >= 2 else { return [] }

        var found: [URL] = []
        var seen = Set<String>()
        for base in bases {
            descend(base, components[...], accepts: accepts, found: &found, seen: &seen)
            if found.count >= limit { break }
        }
        return rank(found, lastComponent: last)
    }

    /// Files inside `directory` whose names start with `prefix` (no slash). Used
    /// for a bare name selected in a terminal, completed against its folder.
    static func completeName(_ prefix: String, in directories: [URL], accepts: (String) -> Bool) -> [URL] {
        guard prefix.count >= 2, !prefix.contains("/") else { return [] }
        var found: [URL] = []
        var seen = Set<String>()
        for directory in directories {
            descend(directory, [prefix][...], accepts: accepts, found: &found, seen: &seen)
            if found.count >= limit { break }
        }
        return rank(found, lastComponent: prefix)
    }

    // MARK: - Walk

    private static func descend(_ directory: URL, _ components: ArraySlice<String>,
                                accepts: (String) -> Bool, found: inout [URL], seen: inout Set<String>) {
        guard let component = components.first, found.count < limit else { return }
        let rest = components.dropFirst()
        let fm = FileManager.default

        if rest.isEmpty {
            // Last component: a file name that may be cut off anywhere.
            for name in entries(of: directory) where hasPrefix(name, component) {
                let url = directory.appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
                let ext = (name as NSString).pathExtension.lowercased()
                let isPackage = isDirectory.boolValue
                    && ((try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false)
                guard (!isDirectory.boolValue || isPackage), accepts(ext),
                      seen.insert(url.standardizedFileURL.path).inserted else { continue }
                found.append(url)
                if found.count >= limit { return }
            }
            return
        }

        // Intermediate component: the exact folder first, then folders it starts.
        let exact = directory.appendingPathComponent(component, isDirectory: true)
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: exact.path, isDirectory: &isDirectory), isDirectory.boolValue {
            descend(exact, rest, accepts: accepts, found: &found, seen: &seen)
            if found.count >= limit { return }
        }
        var branches = 0
        for name in entries(of: directory) where hasPrefix(name, component) && name != component {
            let url = directory.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            descend(url, rest, accepts: accepts, found: &found, seen: &seen)
            branches += 1
            if found.count >= limit || branches >= maxFolderBranches { return }
        }
    }

    private static func entries(of directory: URL) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
              names.count <= maxEntries else { return [] }
        return names
    }

    private static func hasPrefix(_ name: String, _ prefix: String) -> Bool {
        name.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Exact stem first, then the shortest names (closest to what was typed),
    /// newest first among equals.
    private static func rank(_ urls: [URL], lastComponent: String) -> [URL] {
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let wanted = lastComponent.lowercased()
        return urls.sorted { a, b in
            let an = a.lastPathComponent.lowercased(), bn = b.lastPathComponent.lowercased()
            let aExact = an == wanted || (an as NSString).deletingPathExtension == wanted
            let bExact = bn == wanted || (bn as NSString).deletingPathExtension == wanted
            if aExact != bExact { return aExact }
            if an.count != bn.count { return an.count < bn.count }
            return modified(a) > modified(b)
        }
    }
}
