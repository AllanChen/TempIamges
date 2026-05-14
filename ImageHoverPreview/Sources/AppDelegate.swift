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
    private var historyWindow: HistoryWindow?
    private var fileNameResolver: FileNameResolver?
    /// Strong refs to viewer windows opened from a single-hit shortcut so
    /// they outlive the activation that created them.
    private var viewerWindows: [ContentViewerWindow] = []
    #if DEBUG
    private var debugInputWindow: DebugInputWindow?
    #endif

    private var currentPath: String?
    private var isLoadingImage: Bool = false
    /// Last selection text we successfully read via AX. Used as a fallback
    /// when AX returns nothing on a subsequent hotkey press — e.g. after the
    /// user clicked through to a markdown / webpage viewer (which briefly
    /// stole focus) and pressed Control again on the original selection,
    /// some apps clear the selection on focus loss.
    private var lastSelectedText: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        writeDebugMarker("App launched"); Logger.info("AppDelegate: Application did finish launching")
        applyTheme()
        setupComponents()
        setupNotifications()
        checkPermissions()

        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showDebugInputWindow()
        }
        #endif
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
        // Toggle: if a preview is already visible, dismiss it. Otherwise
        // start a fresh preview cycle.
        if let panel = previewPanel, panel.isVisible {
            panel.closePanel()
            previewModeDeactivated()
            return
        }
        activatePreview(injectedText: nil)
    }

    /// Core preview pipeline. When `injectedText` is non-nil, skips AX
    /// selection extraction and uses the provided text — useful for debug
    /// flows that want to exercise PathDetector with a known input.
    private func activatePreview(injectedText: String?) {
        Logger.info("AppDelegate: Preview mode activated\(injectedText != nil ? " (debug)" : "")")
        guard Preferences.shared.enabled else {
            Logger.info("AppDelegate: Preview disabled in preferences")
            return
        }

        let mousePos = currentCursorAXPoint()
        // Debug mode pipes in pre-baked text. Anchor at screen centre.
        let selected: String
        let anchor: CGPoint
        if let text = injectedText {
            selected = text
            if let screen = NSScreen.main {
                // Park the preview on the right half of the screen so the
                // debug input window (top-left) stays visible.
                let f = screen.frame
                anchor = CGPoint(x: f.midX + f.width * 0.2, y: f.midY)
            } else {
                anchor = mousePos
            }
        } else {
            let permissionManager = PermissionManager.shared
            guard permissionManager.isInputMonitoringGranted else {
                Logger.info("AppDelegate: Cannot activate preview - Input Monitoring permission not granted")
                return
            }
            guard permissionManager.isAccessibilityGranted else {
                Logger.info("AppDelegate: Cannot activate preview - Accessibility permission not granted")
                return
            }

            // Try the live AX selection first; cache it on success.
            let axResult = selectedTextExtractor?.extractSelection()
            if let result = axResult, !result.text.isEmpty {
                selected = result.text
                lastSelectedText = result.text
                anchor = mousePos
            } else if let cached = lastSelectedText, !cached.isEmpty {
                // AX returned nothing — fall back to the previous selection
                // we remembered. This handles the "viewed a viewer window,
                // returned, pressed Control" case where some apps drop the
                // selection on focus change.
                Logger.info("AppDelegate: AX empty — falling back to cached selection")
                selected = cached
                anchor = mousePos
            } else {
                Logger.info("AppDelegate: No selected text to preview")
                showErrorTooltip(message: "No text selected", at: mousePos)
                return
            }
        }

        let allHits = pathDetector?.detectAll(selected) ?? []
        let resolved = allHits.filter { $0.url != nil }
        let unresolvedTokens = allHits.compactMap { $0.unresolvedToken }
        Logger.info("AppDelegate: detected \(resolved.count) resolved + \(unresolvedTokens.count) unresolved")

        if resolved.isEmpty && unresolvedTokens.isEmpty {
            Logger.info("AppDelegate: No media path in selected text")
            currentPath = selected
            showErrorTooltip(message: "No image or video found in selection", at: anchor)
            return
        }

        if unresolvedTokens.isEmpty {
            // Fast path: only concrete URLs/paths — preview immediately.
            currentPath = resolved.compactMap { $0.url?.absoluteString }.joined(separator: "|")
            HistoryManager.shared.record(selectedText: selected, detectedPaths: resolved)
            if resolved.count == 1, shouldDirectOpen(resolved[0]) {
                // Single hit (non-webpage) — skip the preview panel and
                // dispatch straight to the click action.
                previewPanel?.hidePanel()
                directOpen(resolved[0])
                return
            }
            loadAndShowMedia(paths: resolved, at: anchor)
            return
        }

        // Mixed (or unresolved-only): show placeholder, Spotlight-resolve
        // unresolved tokens, then preview the combined list.
        currentPath = (resolved.compactMap { $0.url?.absoluteString } + unresolvedTokens).joined(separator: "|")
        resolveAndShow(selectedText: selected, resolved: resolved, tokens: unresolvedTokens, at: anchor)
    }

    private func resolveAndShow(selectedText: String,
                                 resolved: [DetectedPath],
                                 tokens: [String],
                                 at anchor: CGPoint) {
        let totalCount = resolved.count + tokens.count
        let placeholders = (0..<totalCount).map { _ in
            MediaInfo(url: URL(fileURLWithPath: "/"), isLocal: true, kind: .image,
                      dimensions: CGSize(width: 300, height: 533), fileSize: nil, duration: nil)
        }
        previewPanel?.showLoading(infos: placeholders, at: anchor)

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
            // Round-robin pick from each token's match list.
            let maxFromSpotlight = max(0, 24 - resolved.count)
            var spotlight: [FileNameResolver.Match] = []
            var cursors = Array(repeating: 0, count: uniqueTokens.count)
            outer: while spotlight.count < maxFromSpotlight {
                var advanced = false
                for (i, token) in uniqueTokens.enumerated() {
                    let list = resultsByToken[token] ?? []
                    if cursors[i] < list.count {
                        spotlight.append(list[cursors[i]])
                        cursors[i] += 1
                        advanced = true
                        if spotlight.count >= maxFromSpotlight { break outer }
                    }
                }
                if !advanced { break }
            }

            // Spotlight matches → DetectedPath, then append to the already-resolved list.
            let spotlightPaths: [DetectedPath] = spotlight.map { match in
                self.pathDetector?.localKind(for: match.url.path) ?? .localImage(match.url)
            }
            let combined = resolved + spotlightPaths

            guard !combined.isEmpty else {
                self.previewPanel?.hidePanel()
                let label = uniqueTokens.first ?? ""
                self.showErrorTooltip(
                    message: "No file found matching '\(label)'",
                    at: anchor
                )
                return
            }

            HistoryManager.shared.record(selectedText: selectedText, detectedPaths: combined)
            if combined.count == 1, self.shouldDirectOpen(combined[0]) {
                // Same single-hit shortcut as the fast path — drop the
                // placeholder masonry skeletons and open directly.
                self.previewPanel?.hidePanel()
                self.directOpen(combined[0])
                return
            }
            self.loadAndShowMedia(paths: combined, at: anchor)
            // Apply per-tile hints for Spotlight matches — they sit AFTER the
            // pre-resolved ones in the combined list.
            for (offset, match) in spotlight.enumerated() {
                let tileIndex = resolved.count + offset
                let hint = Self.disambiguationHint(for: match.url)
                self.previewPanel?.applyHint(at: tileIndex, hint: hint)
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
        return NSEvent.mouseLocation
    }

    @objc private func previewModeDeactivated() {
        Logger.info("AppDelegate: Preview mode deactivated")
        // With the pin button removed the panel stays visible after the
        // hotkey is released.  It is only dismissed by clicking the X
        // button or by re-pressing the hotkey (toggle).
        errorTooltip?.hide()
        fileNameResolver?.cancelAll()
        currentPath = nil
        isLoadingImage = false
        lastSelectedText = nil
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

    /// Returns true only for markdown / text / PDF — these open straight into
    /// the viewer window.  Every other kind (image, video, webpage, app, etc.)
    /// renders in the preview panel first; the user must click the tile to
    /// trigger the open action.
    private func shouldDirectOpen(_ path: DetectedPath) -> Bool {
        switch path {
        case .localMarkdown, .remoteMarkdown,
             .localText,     .remoteText,
             .localPDF,      .remotePDF:
            return true
        default:
            return false
        }
    }

    /// One-hit shortcut: when path detection settles on exactly one file,
    /// bypass the preview panel and perform the same action that clicking
    /// the tile would have triggered.
    private func directOpen(_ path: DetectedPath) {
        guard let info = MediaInfo.from(path) else { return }
        Logger.info("AppDelegate: single-hit shortcut → opening \(info.url.absoluteString)")
        switch info.kind {
        case .image, .video:
            // Local → default app (Preview / QuickTime). Remote → browser.
            NSWorkspace.shared.open(info.url)
        case .markdown, .text, .pdf:
            openInViewerWindow(info: info)
        case .webPage:
            // Webpages never open directly — they always go through the
            // preview panel so the user sees the URL before deciding to open.
            break
        case .other:
            if info.isLocal {
                NSWorkspace.shared.activateFileViewerSelecting([info.url])
            } else {
                NSWorkspace.shared.open(info.url)
            }
        }
    }

    /// Spawn a ContentViewerWindow and own it until the user closes it.
    /// Mirrors PreviewPanel.openInViewer but lives on AppDelegate so it can
    /// be invoked without the preview panel ever appearing.
    private func openInViewerWindow(info: MediaInfo) {
        let window = ContentViewerWindow()
        switch info.kind {
        case .markdown: window.loadMarkdown(info.url)
        case .text:     window.loadText(info.url)
        case .pdf:      window.loadPDF(info.url)
        case .webPage:  window.loadWebPage(info.url)
        default:        return
        }
        viewerWindows.append(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self = self, let window = window else { return }
            self.viewerWindows.removeAll { $0 === window }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showErrorTooltip(message: String, at position: CGPoint) {
        previewPanel?.hidePanel()
        errorTooltip?.show(message: message, at: position)
    }

    @objc private func preferencesChanged() {
        if !Preferences.shared.enabled {
            previewModeDeactivated()
        }
        applyTheme()
    }

    /// Pin the app to the user's chosen appearance (or release it back to
    /// the system default). NSApp.appearance propagates to every window,
    /// which is what the preview panel and history view read when picking
    /// dynamic / semantic colours.
    private func applyTheme() {
        NSApp.appearance = Preferences.shared.theme.appearance
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

    func openHistory() {
        if historyWindow == nil {
            historyWindow = HistoryWindow()
        }
        historyWindow?.refresh()
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    #if DEBUG
    /// Pops up the debug input window. Each Run click pipes the text view
    /// contents through PathDetector → preview, no hotkey needed.
    private func showDebugInputWindow() {
        let win = debugInputWindow ?? DebugInputWindow()
        win.onRun = { [weak self] text in
            self?.activatePreview(injectedText: text)
        }
        win.setText(debugSamplePrefill)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        debugInputWindow = win
    }

    private var debugSamplePrefill: String {
        return """
        https://resouces.pppron.com/0434049c-d9e7-4a36-9e68-4f8a3faad7b4.jpg


        https://cdn.v2ex.com/avatar/8b6e/2852/785555_xlarge.png

        orn-frontend % '/Users/lily/Desktop/work/HoopCut/data/debug/frame_00375.jpg'

        org_img = "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/572ac945-2e08-4629-b179-f62a388b2f70.jpg"
            target_img = "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/f3e5e1d6-d223-4219-bd4f-67ad0231a578.webp"



            org_img = "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/6461e4f5-8451-4485-b109-44742398f610.jpg"
            target_img = "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/73b7ff2d-ffa0-42d7-8ba5-994bbdbde4e0.png"


            org_img = "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/6461e4f5-8451-4485-b109-44742398f610.jpg"
            target_img = "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/76516dd2-0460-4f4d-bceb-9860fa054b58.png"


            xporn/README.md

            https//www.himarts.com

            xporn/base_image.json

            /Users/lily/Desktop/work/xporn/base_video.json

        ❯ 那我现在每天的工作计划是看哪一个markdown ？

        ⏺ 主入口: websiteseo/week_5_13_action_card.md


          websiteseo/
          ├── plan_v6.md ← 唯一日常入口
          │   ├── 战略 / 12 周路线图
          │   ├── 5/13 重构 (双轨)
          │   ├── 📅 本周日程 5/13-5/19 ← 每天看这一节
          │   └── 引用资料库表 ← 指向以下文件
          │
          ├── trafficjunky_creatives.md     ← 资产库
          ├── adult_directories_submission.md ← 资产库
          ├── tg_content_4weeks.md          ← 资产库
          ├── trafficjunky_tracking_setup.md ← 代码规范
          └── content/blog/best-gay-ai-video-generator-2026.md ← 博客
          这是你每天打开的唯一一个文件。其他都是参考资料库，按需查阅。

          文档结构

          📌 每天打开 → week_5_13_action_card.md
                          │
                          │ 引用以下"按需查阅"资料：
                          │
                          ├── 写博客时    → content/blog/best-gay-ai-video-generator-2026.md
                          ├── 做 Banner 时 → trafficjunky_creatives.md
                          ├── 提交目录时   → adult_directories_submission.md
                          ├── 发 TG 帖时   → tg_content_4weeks.md
                          ├── 部署代码时   → trafficjunky_tracking_setup.md
                          ├── 看大方向时   → plan_v6.md (5/13 重构小节)
                          └── 看整体战略   → ~/.claude/plans/plan-v6-lazy-rossum.md
        """
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
