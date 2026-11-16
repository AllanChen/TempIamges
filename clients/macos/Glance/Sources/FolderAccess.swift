import AppKit

/// The account's real home folder. Inside the App Sandbox `NSHomeDirectory()`
/// and `~` point at the app's container, which never holds the user's files,
/// so path detection and file search must use this instead. Outside the
/// sandbox both are the same folder.
enum UserHome {
    static let path: String = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }()

    /// Expands a leading `~` or `~/` against the real home folder.
    static func expandingTilde(_ input: String) -> String {
        if input == "~" { return path }
        if input.hasPrefix("~/") { return path + input.dropFirst() }
        return (input as NSString).expandingTildeInPath
    }
}

#if MAS
/// Folders the user granted to the sandboxed Mac App Store build. Each grant
/// is a security-scoped bookmark that is opened at launch and kept open for
/// the app's lifetime, so every read below a granted folder just works.
final class FolderAccess {
    static let shared = FolderAccess()

    private let bookmarksKey = "SandboxFolderBookmarks"
    private let promptedKey = "SandboxFolderAccessPrompted"
    private let lock = NSLock()
    private var roots: [String] = []

    var hasAnyGrant: Bool {
        lock.lock(); defer { lock.unlock() }
        return !roots.isEmpty
    }

    /// Reopens the saved grants. Call once at launch.
    func restore() {
        let saved = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
        var kept: [Data] = []
        for data in saved {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else {
                Logger.info("FolderAccess: dropped a folder grant that no longer resolves")
                continue
            }
            let refreshed = stale ? try? url.bookmarkData(options: .withSecurityScope,
                                                          includingResourceValuesForKeys: nil,
                                                          relativeTo: nil) : nil
            kept.append(refreshed ?? data)
            addRoot(url)
        }
        UserDefaults.standard.set(kept, forKey: bookmarksKey)
        Logger.info("FolderAccess: restored \(kept.count) folder grant(s)")
    }

    /// Whether a granted folder contains `path`.
    func covers(_ path: String) -> Bool {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        lock.lock(); defer { lock.unlock() }
        return roots.contains { root in
            target == root || target.hasPrefix(root == "/" ? root : root + "/")
        }
    }

    /// The first absolute, `~/` or `file://` path in `text` that the sandbox
    /// can't read and no grant covers, so Peek can ask for its folder instead
    /// of reporting that nothing was found.
    func firstUncoveredPath(in text: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'`()<>[]{}"))
        for raw in text.components(separatedBy: separators) {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: ",;:"))
            let path: String
            if token.lowercased().hasPrefix("file://"), let url = URL(string: token), url.isFileURL {
                path = url.path
            } else if token.hasPrefix("~/") {
                path = UserHome.expandingTilde(token)
            } else if token.hasPrefix("/"), token.count > 1 {
                path = token
            } else {
                continue
            }
            if FileManager.default.isReadableFile(atPath: path) || covers(path) { continue }
            return path
        }
        return nil
    }

    /// The folder to offer for `path`: the home folder for anything inside it
    /// (one grant then covers every later Peek), the volume for external
    /// drives, otherwise the file's own folder.
    static func suggestedFolder(for path: String) -> URL {
        let home = UserHome.path
        if path == home || path.hasPrefix(home + "/") {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        let components = (path as NSString).pathComponents
        if components.count >= 3, components[1] == "Volumes" {
            return URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(3))),
                       isDirectory: true)
        }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }

    /// Shows the system Open panel so the user can grant a folder. `suggested`
    /// is the folder the panel opens on; pressing the button without picking
    /// a subfolder grants that folder.
    func requestAccess(suggesting suggested: URL? = nil, reason: String? = nil,
                       completion: @escaping (Bool) -> Void = { _ in }) {
        UserDefaults.standard.set(true, forKey: promptedKey)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = suggested ?? URL(fileURLWithPath: UserHome.path, isDirectory: true)
        panel.prompt = "Grant Access".localized
        panel.message = reason
            ?? "Choose a folder Glance can preview files from. Choosing your home folder lets Peek open files anywhere inside it.".localized
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else {
                completion(false)
                return
            }
            completion(self.grant(url))
        }
    }

    /// Asks for a folder once, after the first-run guide, if none is granted.
    func requestOnceIfNeeded() {
        guard !hasAnyGrant, !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        requestAccess()
    }

    private func grant(_ url: URL) -> Bool {
        if covers(url.path) { return true }
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else {
            Logger.error("FolderAccess: could not save access to \(Logger.redact(url.path))")
            return false
        }
        _ = url.startAccessingSecurityScopedResource()
        var saved = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
        saved.append(data)
        UserDefaults.standard.set(saved, forKey: bookmarksKey)
        addRoot(url)
        Logger.info("FolderAccess: granted \(Logger.redact(url.path))")
        return true
    }

    private func addRoot(_ url: URL) {
        let path = url.standardizedFileURL.path
        lock.lock(); defer { lock.unlock() }
        if !roots.contains(path) { roots.append(path) }
    }
}
#endif
