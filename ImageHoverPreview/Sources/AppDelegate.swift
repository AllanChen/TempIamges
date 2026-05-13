import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, StatusBarControllerDelegate {
    private var statusBarController: StatusBarController?
    private var keyboardMonitor: KeyboardMonitor?
    private var selectedTextExtractor: SelectedTextExtractor?
    private var pathDetector: PathDetector?
    private var imageLoader: ImageLoader?
    private var previewPanel: PreviewPanel?
    private var errorTooltip: ErrorTooltip?
    private var onboardingWindow: OnboardingWindow?
    private var preferencesWindow: PreferencesWindow?
    private var fileNameResolver: FileNameResolver?

    private var currentPath: String?
    private var isLoadingImage: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        writeDebugMarker("App launched"); Logger.info("AppDelegate: Application did finish launching")
        setupComponents()
        setupNotifications()
        checkPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor?.stopMonitoring()
    }

    private func setupComponents() {
        statusBarController = StatusBarController()
        statusBarController?.delegate = self

        keyboardMonitor = KeyboardMonitor()
        selectedTextExtractor = SelectedTextExtractor()
        pathDetector = PathDetector()
        imageLoader = ImageLoader()
        previewPanel = PreviewPanel()
        errorTooltip = ErrorTooltip()
        fileNameResolver = FileNameResolver()

        Logger.info("AppDelegate: All components initialized")
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(previewModeActivated),
            name: KeyboardMonitor.previewModeDidActivate,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(previewModeDeactivated),
            name: KeyboardMonitor.previewModeDidDeactivate,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: .preferencesDidChange,
            object: nil
        )

        Logger.info("AppDelegate: Notifications setup complete")
    }

    private func checkPermissions() {
        let permissionManager = PermissionManager.shared

        let needsOnboarding = !permissionManager.isInputMonitoringGranted || !permissionManager.isAccessibilityGranted
        let dontShowAgain = UserDefaults.standard.bool(forKey: "dontShowOnboardingAgain")

        if needsOnboarding && !dontShowAgain {
            showOnboardingWindow()
        }

        if permissionManager.isInputMonitoringGranted {
            startKeyboardMonitoring()
        } else {
            Logger.info("AppDelegate: Input Monitoring permission not granted - keyboard monitoring disabled")
        }
    }

    private func showOnboardingWindow() {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        onboardingWindow?.orderFrontRegardless()
    }

    private func startKeyboardMonitoring() {
        guard let monitor = keyboardMonitor else { return }

        if monitor.startMonitoring() {
            Logger.info("AppDelegate: Keyboard monitoring started")
        } else {
            Logger.info("AppDelegate: Failed to start keyboard monitoring")
        }
    }

    @objc private func previewModeActivated() {
        Logger.info("AppDelegate: Preview mode activated")
        guard Preferences.shared.enabled else {
            Logger.info("AppDelegate: Preview disabled in preferences")
            return
        }

        let permissionManager = PermissionManager.shared
        guard permissionManager.isInputMonitoringGranted else {
            Logger.info("AppDelegate: Cannot activate preview - Input Monitoring permission not granted")
            return
        }
        guard permissionManager.isAccessibilityGranted else {
            Logger.info("AppDelegate: Cannot activate preview - Accessibility permission not granted")
            return
        }

        let mousePos = currentCursorAXPoint()
        guard let result = selectedTextExtractor?.extractSelection() else {
            Logger.info("AppDelegate: No selected text to preview")
            showErrorTooltip(message: "No text selected", at: mousePos)
            return
        }
        let selected = result.text

        // Always anchor the preview at the mouse cursor — feels more natural
        // for a hover-style preview than snapping to the selection bounds.
        let anchor = mousePos

        let allHits = pathDetector?.detectAll(selected) ?? []
        let resolved = allHits.filter { $0.url != nil }
        let unresolvedTokens = allHits.compactMap { $0.unresolvedToken }

        if !resolved.isEmpty {
            // Fast path: concrete URLs / absolute paths — preview immediately,
            // no Spotlight roundtrip.
            Logger.info("AppDelegate: Loading \(resolved.count) media item(s) from selection")
            currentPath = resolved.compactMap { $0.url?.absoluteString }.joined(separator: "|")
            loadAndShowMedia(paths: resolved, at: anchor)
            return
        }

        if unresolvedTokens.isEmpty {
            Logger.info("AppDelegate: No media path in selected text")
            currentPath = selected
            showErrorTooltip(message: "No image or video found in selection", at: anchor)
            return
        }

        Logger.info("AppDelegate: Resolving \(unresolvedTokens.count) unresolved token(s) via Spotlight")
        currentPath = unresolvedTokens.joined(separator: "|")
        resolveAndShow(tokens: unresolvedTokens, at: anchor)
    }

    /// Show a placeholder preview tile, run Spotlight, then re-show the panel
    /// with the resolved tiles. If nothing matches, hide the panel and show
    /// the standard error tooltip.
    private func resolveAndShow(tokens: [String], at anchor: CGPoint) {
        // 1. Immediate placeholder — masonry-mode panel with two skeletons so
        //    the user sees activity within the first frame.
        let placeholder = MediaInfo(
            url: URL(fileURLWithPath: "/"),
            isLocal: true, kind: .image,
            dimensions: CGSize(width: 200, height: 200),
            fileSize: nil, duration: nil
        )
        previewPanel?.showLoading(infos: [placeholder, placeholder], at: anchor)

        let uniqueTokens = NSOrderedSet(array: tokens).array as? [String] ?? tokens

        let group = DispatchGroup()
        var resultsByToken: [String: [FileNameResolver.Match]] = [:]
        for token in uniqueTokens {
            group.enter()
            fileNameResolver?.resolve(token: token) { matches in
                resultsByToken[token] = matches
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // Round-robin: pick the top match from each token first, then the
            // 2nd-best from each, etc. Ensures every distinct filename in the
            // selection gets at least one tile before we double-up on any.
            // Cap is generous so a single filename with many matches surfaces
            // all of them (user can scroll the masonry).
            let maxTiles = 24
            var limited: [FileNameResolver.Match] = []
            var cursors = Array(repeating: 0, count: uniqueTokens.count)
            outer: while limited.count < maxTiles {
                var advanced = false
                for (i, token) in uniqueTokens.enumerated() {
                    let list = resultsByToken[token] ?? []
                    if cursors[i] < list.count {
                        limited.append(list[cursors[i]])
                        cursors[i] += 1
                        advanced = true
                        if limited.count >= maxTiles { break outer }
                    }
                }
                if !advanced { break }
            }
            guard !limited.isEmpty else {
                self.previewPanel?.hidePanel()
                let label = uniqueTokens.first ?? ""
                self.showErrorTooltip(
                    message: "No file found matching '\(label)'",
                    at: anchor
                )
                return
            }

            let paths: [DetectedPath] = limited.compactMap { match in
                let ext = match.url.pathExtension.lowercased()
                if ["mp4", "mov", "m4v", "webm"].contains(ext) { return .localVideo(match.url) }
                if ["md", "markdown"].contains(ext)            { return .localMarkdown(match.url) }
                return .localImage(match.url)
            }
            self.loadAndShowMedia(paths: paths, at: anchor)
            // Apply per-tile hints (parent dir) once the panel has rebuilt.
            for (i, match) in limited.enumerated() {
                let hint = Self.disambiguationHint(for: match.url)
                self.previewPanel?.applyHint(at: i, hint: hint)
            }
        }
    }

    /// Renders a short hint for the tile metadata, e.g.
    /// `/Users/lily/Desktop/work/HoopCut/img.png` → `~/Desktop/work/HoopCut`.
    /// Truncates to the last 2 components if the tildified path is long.
    private static func disambiguationHint(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        var tildified = parent
        if parent == home {
            tildified = "~"
        } else if parent.hasPrefix(home + "/") {
            tildified = "~" + parent.dropFirst(home.count)
        }
        if tildified.count > 24 {
            let comps = (tildified as NSString).pathComponents
            // Last 2 components, prefixed with "…/" so it's clearly truncated.
            if comps.count >= 3 {
                return "…/" + comps.suffix(2).joined(separator: "/")
            }
        }
        return tildified
    }

    private func currentCursorAXPoint() -> CGPoint {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }) ?? NSScreen.main else {
            return location
        }
        let axX = location.x
        let axY = screen.frame.height - (location.y - screen.frame.minY)
        return CGPoint(x: axX, y: axY)
    }

    @objc private func previewModeDeactivated() {
        Logger.info("AppDelegate: Preview mode deactivated")
        previewPanel?.hidePanel()
        errorTooltip?.hide()
        fileNameResolver?.cancelAll()
        currentPath = nil
        isLoadingImage = false
    }

    private func loadAndShowMedia(paths: [DetectedPath], at position: CGPoint) {
        guard !isLoadingImage else { return }
        isLoadingImage = true

        errorTooltip?.hide()

        let infos = paths.compactMap { MediaInfo.from($0) }
        guard !infos.isEmpty else {
            isLoadingImage = false
            showErrorTooltip(message: "No media to preview", at: position)
            return
        }

        // Show panel immediately with loading skeletons; populate per-item as
        // the loader streams results back.
        previewPanel?.showLoading(infos: infos, at: position)

        var loadedCount = 0
        imageLoader?.loadMedia(from: paths,
            onProgress: { [weak self] index, media in
                self?.previewPanel?.updateTile(at: index, with: media)
                if media != nil { loadedCount += 1 }
            },
            onComplete: { [weak self] in
                self?.isLoadingImage = false
                Logger.info("AppDelegate: Loaded \(loadedCount)/\(paths.count) media")
                if loadedCount == 0 {
                    self?.previewPanel?.hidePanel()
                    self?.showErrorTooltip(message: "Failed to load media", at: position)
                }
            }
        )
    }

    private func showErrorTooltip(message: String, at position: CGPoint) {
        previewPanel?.hidePanel()
        errorTooltip?.show(message: message, at: position)
    }

    @objc private func preferencesChanged() {
        if !Preferences.shared.enabled {
            previewModeDeactivated()
        }
    }

    func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func checkAndRequestPermissions() {
        let permissionManager = PermissionManager.shared

        if !permissionManager.isInputMonitoringGranted || !permissionManager.isAccessibilityGranted {
            showOnboardingWindow()
        }
    }

    func clearImageCache() {
        imageLoader?.clearCache()
        Logger.info("AppDelegate: image cache cleared")
    }

    #if DEBUG
    private func runDebugPreview() {
        // Edit this list to test different scenarios. Items can be remote
        // URLs (http/https) or local file paths (starting with "/").
        let entries: [String] = [
            "https://resouces.pppron.com/0434049c-d9e7-4a36-9e68-4f8a3faad7b4.jpg",
            "https://cdn.v2ex.com/avatar/8b6e/2852/785555_xlarge.png",
            "/Users/lily/Desktop/work/HoopCut/data/debug/frame_00375.jpg",
            "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/572ac945-2e08-4629-b179-f62a388b2f70.jpg",
            "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/f3e5e1d6-d223-4219-bd4f-67ad0231a578.webp",
            "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/6461e4f5-8451-4485-b109-44742398f610.jpg",
            "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/73b7ff2d-ffa0-42d7-8ba5-994bbdbde4e0.png",
            "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/6461e4f5-8451-4485-b109-44742398f610.jpg",
            "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/76516dd2-0460-4f4d-bceb-9860fa054b58.png"
        ]
        let paths: [DetectedPath] = entries.compactMap { entry in
            if entry.hasPrefix("/") {
                return .localImage(URL(fileURLWithPath: entry))
            }
            guard let url = URL(string: entry) else { return nil }
            return .remoteImage(url)
        }
        guard let screen = NSScreen.main else { return }
        let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        loadAndShowMedia(paths: paths, at: center)
    }
    #endif
}

// MARK: - Debug Extension
extension AppDelegate {
    func writeDebugMarker(_ message: String) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ImageHoverPreview/debug_marker.txt")
        let text = "\(Date()): \(message)\n"
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
