import AppKit
import Carbon

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
    private var hasShownFDAAlertThisSession = false

    /// Global monitor for modifier+click preview (read-only; does not intercept
    /// the click). nil when disabled or permission is missing.
    private var mouseClickMonitor: Any?
    /// De-dupe guard so a double-click (or repeated events at the same spot)
    /// doesn't fire two previews.
    private var lastModifierClickTime: TimeInterval = 0
    private var lastModifierClickPoint: CGPoint = .zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        writeDebugMarker("App launched"); Logger.info("AppDelegate: Application did finish launching")
        applyLanguage()
        applyTheme()
        setupComponents()
        setupNotifications()
        setupDeepLinkHandler()
        checkPermissions()
        // Close any stale preview when the system wakes from sleep.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showDebugInputWindow()
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor?.stopMonitoring()
        if let monitor = mouseClickMonitor {
            NSEvent.removeMonitor(monitor)
            mouseClickMonitor = nil
        }
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: .languageDidChange,
            object: nil
        )

        Logger.info("AppDelegate: Notifications setup complete")
    }

    private func setupDeepLinkHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        Logger.info("AppDelegate: Deep link handler setup complete")
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                         withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: rawURL) else {
            Logger.info("AppDelegate: Received invalid auth callback URL")
            return
        }

        Logger.info("AppDelegate: Received deep link \(url.scheme ?? "")://\(url.host ?? "")\(url.path)")
        AuthManager.shared.handleCallbackURL(url) { result in
            switch result {
            case .success(let session):
                Logger.info("AppDelegate: Auth callback exchanged for session")
                LoginPanel.shared.completeSignIn(session: session)
            case .failure(let error):
                Logger.info("AppDelegate: Auth callback failed: \(error.localizedDescription)")
                LoginPanel.shared.showAuthError(error.localizedDescription)
            }
        }
    }

    private func checkPermissions() {
        let permissionManager = PermissionManager.shared

        let needsOnboarding = !permissionManager.isInputMonitoringGranted
            || !permissionManager.isAccessibilityGranted
            || !permissionManager.isFullDiskAccessGranted
        
        if needsOnboarding {
            showOnboardingWindow()
        }

        if permissionManager.isInputMonitoringGranted {
            startKeyboardMonitoring()
        } else {
            Logger.info("AppDelegate: Input Monitoring permission not granted - keyboard monitoring disabled")
        }

        updateMouseClickMonitoring()
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

    // MARK: - Modifier+click preview (global, read-only)

    /// Start/stop the global left-mouse-down monitor based on the current
    /// preference and Accessibility permission. Safe to call repeatedly.
    private func updateMouseClickMonitoring() {
        let wantEnabled = Preferences.shared.clickToPreview
            && PermissionManager.shared.isAccessibilityGranted

        if wantEnabled {
            guard mouseClickMonitor == nil else { return }
            // A *global* monitor is read-only: it observes clicks headed to other
            // apps without consuming them, so it never breaks an app's own
            // modifier-click and satisfies the "don't intercept" design choice.
            mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                self?.handleGlobalMouseDown(event)
            }
            Logger.info("AppDelegate: Modifier+click monitoring started")
        } else {
            if let monitor = mouseClickMonitor {
                NSEvent.removeMonitor(monitor)
                mouseClickMonitor = nil
                Logger.info("AppDelegate: Modifier+click monitoring stopped")
            }
        }
    }

    /// Runs on the main thread (NSEvent global monitor). Keep the synchronous
    /// part cheap: gate on modifiers, then hand off the heavy AX read async.
    private func handleGlobalMouseDown(_ event: NSEvent) {
        guard Preferences.shared.enabled, Preferences.shared.clickToPreview else { return }

        // Require exactly the activation modifiers — same set the keyboard
        // hotkey uses — so click and hotkey stay consistent.
        let required = Preferences.shared.effectiveModifiers
        guard !required.isEmpty else { return }
        let deviceIndependent = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard deviceIndependent.intersection(relevant) == required.intersection(relevant) else { return }

        let point = NSEvent.mouseLocation

        // De-dupe rapid repeats / double-clicks at (approximately) the same spot.
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastModifierClickTime < 0.3,
           abs(point.x - lastModifierClickPoint.x) < 6,
           abs(point.y - lastModifierClickPoint.y) < 6 {
            return
        }
        lastModifierClickTime = now
        lastModifierClickPoint = point

        handleModifierClick(at: point)
    }

    /// Read text under the cursor (falling back to selection, then clipboard),
    /// then run it through the normal preview pipeline. Silent on total miss so
    /// stray clicks don't spam error tooltips.
    private func handleModifierClick(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }
        guard let extractor = selectedTextExtractor else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var text: String?
            if let cursor = extractor.extractTextAtCursor(at: point), !cursor.text.isEmpty {
                text = cursor.text
            } else if let selection = extractor.extractSelection(), !selection.text.isEmpty {
                Logger.info("AppDelegate: click — cursor text empty, using selection")
                text = selection.text
            } else if Preferences.shared.readClipboard,
                      let clip = extractor.readClipboardDirectly(), !clip.text.isEmpty {
                Logger.info("AppDelegate: click — falling back to clipboard")
                text = clip.text
            }

            guard let resolved = text, !resolved.isEmpty else {
                Logger.info("AppDelegate: click — no text found under cursor; ignoring")
                return
            }

            DispatchQueue.main.async {
                self.lastSelectedText = resolved
                // If a preview is already open, close it first so the new click
                // opens a fresh preview ("click what you see").
                if self.previewPanel?.isVisible ?? false || ContentPanel.shared.isVisible {
                    self.previewPanel?.closePanel()
                    ContentPanel.shared.dismiss()
                }
                self.proceedWithPreview(text: resolved, anchor: point)
            }
        }
    }

    @objc private func previewModeActivated() {
        let previewVisible = previewPanel?.isVisible ?? false
        let contentVisible = ContentPanel.shared.isVisible
        if previewVisible || contentVisible {
            previewPanel?.closePanel()
            ContentPanel.shared.dismiss()
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

        if let text = injectedText {
            let anchor: CGPoint
            if let screen = NSScreen.main {
                let f = screen.frame
                anchor = CGPoint(x: f.midX + f.width * 0.2, y: f.midY)
            } else {
                anchor = mousePos
            }
            proceedWithPreview(text: text, anchor: anchor)
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

        selectedTextExtractor?.extractSelection { [weak self] result in
            guard let self = self else { return }

            let selected: String
            let anchor = mousePos

            if let result = result, !result.text.isEmpty {
                selected = result.text
                self.lastSelectedText = result.text
            } else if let cached = self.lastSelectedText, !cached.isEmpty {
                Logger.info("AppDelegate: AX empty — falling back to cached selection")
                selected = cached
            } else if Preferences.shared.readClipboard,
                      let clipboardResult = self.selectedTextExtractor?.readClipboardDirectly() {
                Logger.info("AppDelegate: AX empty — falling back to clipboard content")
                selected = clipboardResult.text
                self.lastSelectedText = clipboardResult.text
            } else {
                Logger.info("AppDelegate: No selected text to preview")
                self.showErrorTooltip(message: "No text selected".localized, at: mousePos)
                return
            }

            self.proceedWithPreview(text: selected, anchor: anchor)
        }
    }

    private func proceedWithPreview(text selected: String, anchor: CGPoint) {
        let allHits = pathDetector?.detectAll(selected) ?? []
        let resolved = allHits.filter { $0.url != nil }
        let unresolvedTokens = allHits.compactMap { $0.unresolvedToken }
        Logger.info("AppDelegate: detected \(resolved.count) resolved + \(unresolvedTokens.count) unresolved")

        if resolved.isEmpty && unresolvedTokens.isEmpty {
            Logger.info("AppDelegate: No media path in selected text")
            currentPath = selected
            showErrorTooltip(message: "No image or video found in selection".localized, at: anchor)
            return
        }

        if unresolvedTokens.isEmpty {
            currentPath = resolved.compactMap { $0.url?.absoluteString }.joined(separator: "|")
            HistoryManager.shared.record(selectedText: selected, detectedPaths: resolved)
            if resolved.count == 1, shouldDirectOpen(resolved[0]) {
                previewPanel?.closeWithoutAffectingContent()
                directOpen(resolved[0])
                return
            }
            loadAndShowMedia(paths: resolved, at: anchor)
            return
        }

        currentPath = (resolved.compactMap { $0.url?.absoluteString } + unresolvedTokens).joined(separator: "|")
        resolveAndShow(selectedText: selected, resolved: resolved, tokens: unresolvedTokens, at: anchor)
    }

    private func resolveAndShow(selectedText: String,
                                 resolved: [DetectedPath],
                                 tokens: [String],
                                 at anchor: CGPoint) {
        let uniqueTokens = NSOrderedSet(array: tokens).array as? [String] ?? tokens
        
        // 先显示 loading 面板，让用户知道搜索正在进行
        var loadingInfo = MediaInfo(url: URL(fileURLWithPath: "/dev/null"), isLocal: true, kind: .other)
        loadingInfo.searchToken = uniqueTokens.first ?? ""
        self.previewPanel?.showLoading(infos: [loadingInfo], at: anchor)

        // 延迟一帧开始搜索，确保 loading UI 有机会先渲染出来。
        // FileNameResolver.resolve 内部的 quickFilesystemMatches 是同步执行的，
        // 如果在 showLoading 的动画尚未开始前就阻塞主线程，panel 会一直保持
        // alpha = 0，用户就只能等到搜索结束后才看到面板弹出。
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let group = DispatchGroup()
            var resultsByToken: [String: [FileNameResolver.Match]] = [:]
            for token in uniqueTokens {
                group.enter()
                self.fileNameResolver?.resolve(token: token) { matches in
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
                    let label = uniqueTokens.first ?? ""
                    let failMessage = String(format: "No file found matching '%@'".localized, label)
                    self.previewPanel?.updateTile(at: 0, with: nil, failedMessage: failMessage)
                    self.promptForFullDiskAccessIfNeeded()
                    return
                }

                HistoryManager.shared.record(selectedText: selectedText, detectedPaths: combined)
                if combined.count == 1, self.shouldDirectOpen(combined[0]) {
                    // Same single-hit shortcut as the fast path — close PreviewPanel
                    // so the user only sees ContentPanel.
                    self.previewPanel?.closeWithoutAffectingContent()
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
        // 不要取消正在进行的文件搜索 —— 用户释放热键后面板应保持可见，
        // 搜索完成后应自动显示结果。取消搜索会导致文件已找到但无法显示。
        // fileNameResolver?.cancelAll()
        currentPath = nil
        isLoadingImage = false
        lastSelectedText = nil
    }

    @objc private func systemDidWake() {
        Logger.info("AppDelegate: System woke from sleep")
        previewPanel?.closePanel()
        previewModeDeactivated()
    }

    private func loadAndShowMedia(paths: [DetectedPath], at position: CGPoint) {
        guard !isLoadingImage else { return }
        isLoadingImage = true

        errorTooltip?.hide()

        let infos = paths.compactMap { MediaInfo.from($0) }
        guard !infos.isEmpty else {
            isLoadingImage = false
            showErrorTooltip(message: "No media to preview".localized, at: position)
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
                    Logger.info("AppDelegate: All media failed to load, keeping panel visible with error state")
                    let needsFDA = paths.contains { path in
                        guard let url = path.url, url.isFileURL else { return false }
                        return self?.isUnderProtectedDirectory(url) ?? false
                    }
                    if needsFDA && !PermissionManager.shared.isFullDiskAccessGranted {
                        self?.promptForFullDiskAccessIfNeeded()
                    }
                    return
                }
            }
        )
    }

    /// Returns true for single results that ContentPanel can render directly.
    /// Unsupported files still go through PreviewPanel so the user can reveal
    /// or open them from a tile.
    private func shouldDirectOpen(_ path: DetectedPath) -> Bool {
        switch path {
        case .localImage,  .remoteImage,
             .localMarkdown, .remoteMarkdown,
             .localText,     .remoteText,
             .localPDF,      .remotePDF,
             .webPage:
            return true
        default:
            return false
        }
    }

    private func isUnderProtectedDirectory(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.path
        let home = NSHomeDirectory()
        let protected = ["/Desktop", "/Documents", "/Downloads", "/Library"]
        return protected.contains { path.hasPrefix(home + $0) }
    }

    /// One-hit shortcut: when path detection settles on exactly one file,
    /// bypass the preview panel and perform the same action that clicking
    /// the tile would have triggered.
    private func directOpen(_ path: DetectedPath) {
        guard let info = MediaInfo.from(path) else { return }

        if info.isLocal && isUnderProtectedDirectory(info.url)
            && !PermissionManager.shared.isFullDiskAccessGranted {
            promptForFullDiskAccessIfNeeded()
            return
        }

        Logger.info("AppDelegate: single-hit shortcut → opening \(info.url.absoluteString)")
        switch info.kind {
        case .image, .markdown, .text, .pdf, .webPage:
            openInContentPanel(info: info)
        case .video:
            NSWorkspace.shared.open(info.url)
        case .other, .folder:
            if info.isLocal {
                NSWorkspace.shared.activateFileViewerSelecting([info.url])
            } else {
                NSWorkspace.shared.open(info.url)
            }
        }
    }

    private func openInContentPanel(info: MediaInfo) {
        let panel = ContentPanel.shared
        panel.load(info: info)
        panel.orderFrontRegardless()
        panel.makeKey()
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
        updateMouseClickMonitoring()
        applyTheme()
    }

    @objc private func languageChanged() {
        Logger.info("AppDelegate: Language changed to \(Preferences.shared.appLanguage.rawValue)")
        if let oldWindow = preferencesWindow {
            oldWindow.close()
            preferencesWindow = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let newWindow = PreferencesWindow()
            self.preferencesWindow = newWindow
            newWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Apply the user's chosen language by setting AppleLanguages in
    /// UserDefaults before any UI is created.
    private func applyLanguage() {
        let lang = Preferences.shared.appLanguage.rawValue
        UserDefaults.standard.set([lang], forKey: "AppleLanguages")
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
        showOnboardingWindow()
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

    func openLogin(at point: NSPoint) {
        LoginPanel.shared.show(at: point)
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

    private func promptForFullDiskAccessIfNeeded() {
        guard !hasShownFDAAlertThisSession,
              !PermissionManager.shared.isFullDiskAccessGranted else { return }
        hasShownFDAAlertThisSession = true

        let alert = NSAlert()
        alert.messageText = "Full Disk Access Required".localized
        alert.informativeText = "Glance needs Full Disk Access to search files in protected locations (Desktop, Documents, Downloads). Enable it in System Settings to improve search results.".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            PermissionManager.shared.openFullDiskAccessSettings()
        }
    }
}

// MARK: - Debug Extension
extension AppDelegate {
    func writeDebugMarker(_ message: String) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Glance/debug_marker.txt")
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
