import AppKit
import UserNotifications
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate, StatusBarControllerDelegate, UNUserNotificationCenterDelegate {
    var statusBarController: StatusBarController?
    private var keyboardMonitor: KeyboardMonitor?
    private var selectedTextExtractor: SelectedTextExtractor?
    private var pathDetector: PathDetector?
    private var imageLoader: ImageLoader?
    private var previewPanel: PreviewPanel?
    /// Hotkey Peeks of images and videos open this card beside the selection;
    /// ↵ hands off to the full Inspect.
    private var peekMini: PeekMiniPanel?
    /// Set for hotkey requests, which show Peek Mini; nil for Finder opens.
    private var activeAnchor: PeekMiniAnchor?
    /// The last hotkey selection, so a failure card can search again.
    private var lastPeekSelection: (text: String, contextDirectories: [URL], bounds: CGRect?)?
    private var errorTooltip: ErrorTooltip?
    private var onboardingWindow: OnboardingWindow?
    private var preferencesWindow: PreferencesWindow?
    private var historyWindow: HistoryWindow?
    private var homeWindow: HomeWindow?
    private var widgetTaskCenterWindow: WidgetTaskCenterWindow?
    private var fileNameResolver: FileNameResolver?
    private var imageInspectWindow: ImageInspectWindow?
    /// Independent Image Inspect windows that show saved captures. They live
    /// apart from `imageInspectWindow` so a capture never replaces the picture
    /// it was taken from.
    private var captureResultWindows: [ImageInspectWindow] = []
    private var videoCompareWindow: VideoCompareWindow?
    /// Finder/LaunchServices can split one multi-selection into several open
    /// callbacks (notably when extensions/UTIs differ). Coalesce the burst so
    /// later batches cannot replace the earlier images with a two-item Compare.
    private var pendingOpenURLs: [URL] = []
    private var pendingOpenWorkItem: DispatchWorkItem?
    /// Strong refs to viewer windows opened from a single-hit shortcut so
    /// they outlive the activation that created them.
    private var viewerWindows: [ContentViewerWindow] = []

    private var currentPath: String?
    private var isLoadingImage: Bool = false
    /// The app that owned the selection before any Glance window took focus.
    /// Repeat hotkey presses re-read the selection from THIS app via scoped AX,
    /// instead of falling through to whatever happens to be on the clipboard.
    private var lastSourceApp: NSRunningApplication?
    private var hasShownFDAAlertThisSession = false
    private var activeRequestID: UInt64 = 0
    private var activeSelectionText: String?
    private var activeSourceAppName: String?
    private var isCheckingVisibleSelection = false
    private var activeRequestStartedAt = Date()
    private var successfulRequestID: UInt64?
    /// True once launch has settled, so activation (Cmd-Tab / Dock click) may
    /// surface the Home window when nothing else is on screen. Suppressed
    /// briefly while a hotkey request is loading so we don't race the preview.
    private var didFinishInitialLaunch = false
    /// Fresh install: offer the permission guide over Home once launch settles.
    private var firstRunGuidePending = false
    /// The first-run guide is (or was just) on screen; granting Accessibility
    /// from it is the user's opt-in to Peek.
    private var firstRunGuideActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        writeDebugMarker("App launched"); Logger.info("AppDelegate: Application did finish launching")
        applyLanguage()
        applyTheme()
        setupMainMenu()
        #if MAS
        FolderAccess.shared.restore()
        AppStorePurchases.shared.start()
        #else
        AppUpdater.shared.start()
        #endif
        setupComponents()
        UNUserNotificationCenter.current().delegate = self
        setupNotifications()
        setupDeepLinkHandler()
        BillingManager.shared.start()
        // Hide installed Widgets that were taken down while Glance was closed.
        WidgetAvailabilitySync.shared.start()
        AuthManager.shared.refreshAccount()
        // Read before checkPermissions(), whose Peek migration marks the install as set up.
        let isFirstRun = Preferences.shared.consumeFirstRun()
        checkPermissions()
        firstRunGuidePending = isFirstRun && !PermissionManager.shared.canUsePeek
            && !Preferences.shared.permissionSetupDismissed
        // As a regular (Dock/Cmd-Tab) app, a fresh launch with no window would
        // otherwise start in the background. Bring it to the front so `run.sh`
        // visibly focuses the app.
        NSApp.activate(ignoringOtherApps: true)
        // Close any stale preview when the system wakes from sleep.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Allow activation-triggered Home only after launch has settled, so the
        // initial NSApp.activate above doesn't immediately pop Home on top of a
        // fresh launch that may be opening a file. The activation during launch
        // is ignored, so show Home here for a plain launch (Dock, Finder, Spotlight).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            self.didFinishInitialLaunch = true
            if self.pendingOpenURLs.isEmpty, self.pendingOpenWorkItem == nil {
                self.surfaceHomeIfIdle()
            }
            if self.firstRunGuidePending {
                self.firstRunGuidePending = false
                self.firstRunGuideActive = true
                // Queued after Home's deferred presentation so the guide lands on top.
                DispatchQueue.main.async { self.showOnboardingWindow() }
            }
        }

    }

    /// Cmd-Tab / app switch. If Glance becomes active with no content window
    /// on screen, surface the Home launcher — Glance has no document to show
    /// otherwise, so the user would face an empty app.
    func applicationDidBecomeActive(_ notification: Notification) {
        adoptPeekIfGrantedFromFirstRunGuide()
        if Preferences.shared.peekEnabled { startKeyboardMonitoring() }
        if AuthManager.shared.isSignedIn { BillingManager.shared.refreshEntitlements(); BillingManager.shared.refreshWallet(); BillingCoordinator.shared.restorePendingPayments() }
        surfaceHomeIfIdle()
    }

    /// Dock icon click / reopen with no windows.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        surfaceHomeIfIdle()
        return true
    }

    /// Open Home only when the app is truly idle: launch settled, no hotkey
    /// request in flight, and no Glance content window already visible.
    private func surfaceHomeIfIdle() {
        guard didFinishInitialLaunch else { return }
        guard !isLoadingImage, !isCheckingVisibleSelection else { return }
        guard !hasVisibleContentWindow() else { return }
        // Defer one turn so any window that is mid-presentation (and briefly
        // not yet `isVisible`) has settled before we decide it's empty.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.hasVisibleContentWindow() else { return }
            self.openHome()
        }
    }

    /// Whether any Glance-owned content / tool window is currently on screen.
    private func hasVisibleContentWindow() -> Bool {
        if statusBarController?.isTrayVisible == true { return true }
        if previewPanel?.isVisible == true { return true }
        if ContentPanel.shared.isVisible { return true }
        if imageInspectWindow?.isVisible == true { return true }
        if videoCompareWindow?.isVisible == true { return true }
        if widgetTaskCenterWindow?.isVisible == true { return true }
        if historyWindow?.isVisible == true { return true }
        if preferencesWindow?.isVisible == true { return true }
        if onboardingWindow?.isVisible == true { return true }
        if homeWindow?.isVisible == true { return true }
        if viewerWindows.contains(where: { $0.isVisible }) { return true }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor?.stopMonitoring()
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let mediaURLs = urls.filter { url in
            if BillingCoordinator.shared.handlePaymentReturn(url) { return false }
            if url.scheme == "glance", url.host == "auth" { completeAuthCallback(url); return false }
            return true
        }
        if pathDetector == nil || imageLoader == nil {
            setupComponents()
        }
        pendingOpenURLs.append(contentsOf: mediaURLs)
        pendingOpenWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flushPendingOpenURLs() }
        pendingOpenWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func flushPendingOpenURLs() {
        pendingOpenWorkItem = nil
        var seen = Set<String>()
        let urls = pendingOpenURLs.filter { url in
            let key = url.isFileURL ? url.standardizedFileURL.path : url.absoluteString
            return seen.insert(key).inserted
        }
        pendingOpenURLs.removeAll()

        let detector = pathDetector ?? PathDetector()
        let paths = urls.map { detector.localKind(for: $0.path) }
            .filter {
                guard let info = MediaInfo.from($0) else { return false }
                return info.kind == .image || info.kind == .video
            }
        guard !paths.isEmpty else { return }

        // Opening from Finder counts as viewing: it belongs in Recent like Home opens do.
        HistoryManager.shared.record(selectedText: "", detectedPaths: paths)
        Logger.info("AppDelegate: opening \(paths.count) Finder media item(s) as one batch")
        activeRequestID &+= 1
        activeRequestStartedAt = Date()
        activeSourceAppName = nil
        activeAnchor = nil
        loadAndShowMedia(paths: paths, at: NSEvent.mouseLocation, requestID: activeRequestID)
        offerDefaultViewerIfNeeded()
    }

    private func setupComponents() {
        guard statusBarController == nil else { return }
        statusBarController = StatusBarController()
        statusBarController?.delegate = self

        keyboardMonitor = KeyboardMonitor()
        selectedTextExtractor = SelectedTextExtractor()
        pathDetector = PathDetector()
        imageLoader = ImageLoader()
        previewPanel = PreviewPanel()
        previewPanel?.onInspectImages = { [weak self] infos, loaded, focusedIndex in
            self?.openImageInspect(infos: infos, loaded: loaded, focusedIndex: focusedIndex)
        }
        previewPanel?.onInspectVideos = { [weak self] infos, focusedIndex in
            self?.openVideoCompare(infos: infos, focusedIndex: focusedIndex)
        }
        previewPanel?.onDismiss = { [weak self] in self?.invalidateActiveRequest() }
        let mini = PeekMiniPanel(imageLoader: imageLoader!)
        mini.onInspect = { [weak self] infos, focusedIndex in
            self?.openPeekInspect(infos: infos, focusedIndex: focusedIndex)
        }
        mini.onDismiss = { [weak self] in self?.invalidateActiveRequest() }
        mini.onRetry = { [weak self] in
            guard let self, let last = self.lastPeekSelection else { return }
            self.activatePreview(injectedText: last.text, contextDirectories: last.contextDirectories,
                                 selectionBounds: last.bounds)
        }
        mini.onLoadFinished = { [weak self] succeeded, paths in
            self?.peekMiniDidLoad(succeeded: succeeded, paths: paths)
        }
        mini.failureMessage = { [weak self] url in self?.unreadableFileMessage(for: url) ?? "" }
        peekMini = mini
        errorTooltip = ErrorTooltip()
        fileNameResolver = FileNameResolver()

        Logger.info("AppDelegate: All components initialized")
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onboardingDidClose),
            name: OnboardingWindow.didClose,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(previewModeActivated),
            name: KeyboardMonitor.previewModeDidActivate,
            object: nil
        )
        #if MAS
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyUnavailable),
            name: KeyboardMonitor.hotkeyUnavailable,
            object: nil
        )
        #endif

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
        if BillingCoordinator.shared.handlePaymentReturn(url) { return }
        guard url.scheme == "glance",url.host == "auth" else{return}
        completeAuthCallback(url)
    }
    private func completeAuthCallback(_ url:URL) {
        AuthManager.shared.handleCallbackURL(url) { result in
            switch result {
            case .success(let session):
                Logger.info("AppDelegate: Auth callback exchanged for session")
                _ = session // BillingWindow observes the saved session and resumes its original action.
            case .failure(let error):
                Logger.info("AppDelegate: Auth callback failed: \(error.localizedDescription)")
                BillingCoordinator.shared.showAuthenticationError(error.localizedDescription)
            }
        }
    }

    private var peekWasEnabled = false

    private func checkPermissions() {
        let permissionManager = PermissionManager.shared

        Preferences.shared.migratePeekOptIn(
            alreadySetUp: permissionManager.canUsePeek)
        peekWasEnabled = Preferences.shared.peekEnabled
        // Peek is opt-in. Until it is switched on Glance is a plain viewer and
        // must not ask for (or nag about) any permission.
        guard peekWasEnabled else {
            Logger.info("AppDelegate: Peek is off - no permissions requested")
            return
        }

        let needsOnboarding = !permissionManager.canUsePeek
        
        if needsOnboarding && !Preferences.shared.permissionSetupDismissed {
            showOnboardingWindow()
        }

        if permissionManager.canUsePeek {
            startKeyboardMonitoring()
        } else {
            Logger.info("AppDelegate: Accessibility permission not granted - keyboard monitoring disabled")
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
        // Leaving optional setup must not start a tap that could request the
        // missing permission implicitly. Accessibility also grants event listening.
        guard PermissionManager.shared.canUsePeek else { return }
        guard let monitor = keyboardMonitor else { return }

        if monitor.startMonitoring() {
            Logger.info("AppDelegate: Keyboard monitoring started")
        } else {
            Logger.info("AppDelegate: Failed to start keyboard monitoring")
            #if MAS
            hotkeyUnavailable()
            #endif
        }
    }

    #if MAS
    /// macOS refused the Peek shortcut. Say why and where to pick another one.
    @objc private func hotkeyUnavailable() {
        let alert = NSAlert()
        alert.messageText = "Glance couldn't turn on the Peek shortcut".localized
        alert.informativeText = "macOS didn't allow this shortcut. Recent macOS versions block shortcuts that use only Option (⌥) or Shift. Choose a shortcut that includes Command (⌘) or Control (⌃) in Preferences, then Peek will work right away.".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Preferences".localized)
        alert.addButton(withTitle: "Not Now".localized)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openPreferences()
        }
    }
    #endif

    private var isPeekVisible: Bool {
        (previewPanel?.isVisible ?? false) || (peekMini?.isVisible ?? false)
    }

    private func closePeekSurfaces() {
        previewPanel?.closePanel()
        peekMini?.dismiss()
    }

    @objc private func previewModeActivated() {
        if isPeekVisible {
            if isCheckingVisibleSelection {
                isCheckingVisibleSelection = false
                invalidateActiveRequest()
                closePeekSurfaces()
                return
            }
            if isLoadingImage {
                invalidateActiveRequest()
                closePeekSurfaces()
                return
            }
            isCheckingVisibleSelection = true
            selectedTextExtractor?.extractSelectionFast { [weak self] result in
                guard let self = self, self.isCheckingVisibleSelection else { return }
                self.isCheckingVisibleSelection = false
                guard self.isPeekVisible else { return }
                guard let text = result?.text, !text.isEmpty else {
                    self.invalidateActiveRequest()
                    self.closePeekSurfaces()
                    return
                }
                let normalized = self.normalizedSelection(text)
                if normalized == self.activeSelectionText {
                    self.invalidateActiveRequest()
                    self.closePeekSurfaces()
                } else {
                    self.activatePreview(injectedText: text, contextDirectories: result?.contextDirectories ?? [],
                                         selectionBounds: result?.bounds)
                }
            }
            return
        }
        if ContentPanel.shared.isVisible {
            previewPanel?.closePanel()
            ContentPanel.shared.dismiss()
            return
        }
        activatePreview(injectedText: nil)
    }

    /// Core preview pipeline. When `injectedText` is non-nil, skips AX
    /// selection extraction and reuses text already read during a hotkey refresh.
    private func activatePreview(injectedText: String?, contextDirectories: [URL] = [],
                                 selectionBounds: CGRect? = nil) {
        Logger.info("AppDelegate: Preview mode activated\(injectedText != nil ? " (selection refresh)" : "")")
        guard Preferences.shared.peekEnabled else {
            Logger.info("AppDelegate: Preview disabled in preferences")
            return
        }

        let mousePos = currentCursorAXPoint()
        activeSourceAppName = NSWorkspace.shared.frontmostApplication?.localizedName
        activeRequestID &+= 1
        let requestID = activeRequestID
        activeRequestStartedAt = Date()
        successfulRequestID = nil
        PeekDiagnostics.recordTrigger()
        isLoadingImage = true

        if let text = injectedText {
            activeAnchor = PeekMiniAnchor(axSelection: selectionBounds, pointer: mousePos)
            lastPeekSelection = (text, contextDirectories, selectionBounds)
            let anchor: CGPoint
            if let screen = NSScreen.main {
                let f = screen.frame
                anchor = CGPoint(x: f.midX + f.width * 0.2, y: f.midY)
            } else {
                anchor = mousePos
            }
            proceedWithPreview(text: text, anchor: anchor, requestID: requestID,
                               contextDirectories: contextDirectories)
            return
        }

        let permissionManager = PermissionManager.shared
        guard permissionManager.isAccessibilityGranted else {
            isLoadingImage = false
            Logger.info("AppDelegate: Cannot activate preview - Accessibility permission not granted")
            return
        }

        selectedTextExtractor?.extractSelection(fromPID: sourceAppPIDForSelection()) { [weak self] result in
            guard let self = self, requestID == self.activeRequestID else { return }

            let selected: String
            let anchor = mousePos
            var contextDirectories: [URL] = []

            var bounds: CGRect?
            if let result = result, !result.text.isEmpty {
                selected = result.text
                contextDirectories = result.contextDirectories
                bounds = result.bounds
            } else if Preferences.shared.readClipboard,
                      let clipboardResult = self.selectedTextExtractor?.readClipboardDirectly() {
                Logger.info("AppDelegate: AX empty — falling back to clipboard content")
                selected = clipboardResult.text
            } else {
                Logger.info("AppDelegate: No selected text to preview")
                self.isLoadingImage = false
                PeekDiagnostics.recordUnrecognizedSelection()
                self.showErrorTooltip(message: "No text selected".localized, at: mousePos)
                return
            }

            self.activeAnchor = PeekMiniAnchor(axSelection: bounds, pointer: mousePos)
            self.lastPeekSelection = (selected, contextDirectories, bounds)
            self.proceedWithPreview(text: selected, anchor: anchor, requestID: requestID,
                                    contextDirectories: contextDirectories)
        }
    }

    private func proceedWithPreview(text selected: String, anchor: CGPoint, requestID: UInt64,
                                    contextDirectories: [URL] = []) {
        guard requestID == activeRequestID else { return }
        activeSelectionText = normalizedSelection(selected)
        let detector = pathDetector ?? PathDetector()
        let hits = detector.detectAll(selected, contextDirectories: contextDirectories)
        detector.classifyRemoteLinks(hits) { [weak self] classified in
            self?.previewDetectedPaths(classified, selected: selected, anchor: anchor,
                                       requestID: requestID, contextDirectories: contextDirectories)
        }
    }

    private func previewDetectedPaths(_ allHits: [DetectedPath], selected: String, anchor: CGPoint,
                                      requestID: UInt64, contextDirectories: [URL]) {
        guard requestID == activeRequestID else { return }
        // A bare name selected in a terminal names a file in its working
        // directory (`ls` output): resolve it in the closest folder that has it
        // before searching the disk. A name cut off before its end is
        // completed there too, like Tab in the shell.
        var resolved: [DetectedPath] = []
        var unresolvedTokens: [String] = []
        for hit in allHits {
            if hit.url != nil {
                resolved.append(hit)
            } else if let token = hit.unresolvedToken {
                if let local = contextDirectories.lazy.compactMap({ self.mediaPath(named: token, in: $0) }).first {
                    resolved.append(local)
                } else if !token.contains("/"),
                          let completed = pathDetector?.completeName(token, in: contextDirectories), !completed.isEmpty {
                    resolved.append(contentsOf: completed.filter { path in
                        guard let info = MediaInfo.from(path) else { return false }
                        return info.kind == .image || info.kind == .video
                    })
                    if resolved.isEmpty { unresolvedTokens.append(token) }
                } else {
                    unresolvedTokens.append(token)
                }
            }
        }
        Logger.info("AppDelegate: detected \(resolved.count) resolved + \(unresolvedTokens.count) unresolved")

        if resolved.isEmpty && unresolvedTokens.isEmpty {
            Logger.info("AppDelegate: No media path in selected text")
            isLoadingImage = false
            #if MAS
            if let blocked = FolderAccess.shared.firstUncoveredPath(in: selected) {
                requestFolderAccess(for: blocked, retrying: selected, anchor: anchor,
                                    requestID: requestID, contextDirectories: contextDirectories)
                return
            }
            #endif
            PeekDiagnostics.recordUnrecognizedSelection()
            currentPath = selected
            showErrorTooltip(message: "No image or video found in selection".localized, at: anchor)
            return
        }

        if unresolvedTokens.isEmpty {
            currentPath = resolved.compactMap { $0.url?.absoluteString }.joined(separator: "|")
            HistoryManager.shared.record(selectedText: selected, detectedPaths: resolved)
            if resolved.count == 1, shouldDirectOpen(resolved[0]) {
                previewPanel?.closeWithoutAffectingContent()
                dismissPeekMiniKeepingRequest()
                directOpen(resolved[0])
                return
            }
            loadAndShowMedia(paths: resolved, at: anchor, requestID: requestID)
            return
        }

        #if MAS
        // Searching by name needs at least one readable folder.
        if !FolderAccess.shared.hasAnyGrant {
            isLoadingImage = false
            requestFolderAccess(for: UserHome.path, retrying: selected, anchor: anchor,
                                requestID: requestID, contextDirectories: contextDirectories)
            return
        }
        #endif
        currentPath = (resolved.compactMap { $0.url?.absoluteString } + unresolvedTokens).joined(separator: "|")
        resolveAndShow(selectedText: selected, resolved: resolved, tokens: unresolvedTokens,
                       contextDirectories: contextDirectories, at: anchor, requestID: requestID)
    }

    #if MAS
    /// Peek found a path the sandbox can't read yet: ask for its folder, then
    /// rerun the same selection so the user doesn't have to select it again.
    private func requestFolderAccess(for path: String, retrying text: String, anchor: CGPoint,
                                     requestID: UInt64, contextDirectories: [URL]) {
        previewPanel?.hidePanel()
        let folder = FolderAccess.suggestedFolder(for: path)
        let reason = String(format: "Glance needs your permission to read files in “%@”. Grant access to preview this file now. Files inside this folder won't ask again.".localized,
                            folder.path)
        FolderAccess.shared.requestAccess(suggesting: folder, reason: reason) { [weak self] granted in
            guard let self, requestID == self.activeRequestID else { return }
            guard granted else {
                self.showErrorTooltip(message: "Glance can't read files in this folder. To allow it, choose Glance > Grant Folder Access…".localized,
                                      at: anchor)
                return
            }
            self.isLoadingImage = true
            self.proceedWithPreview(text: text, anchor: anchor, requestID: requestID,
                                    contextDirectories: contextDirectories)
        }
    }
    #endif

    /// `token` (a bare name or relative path) as an existing media file inside `directory`.
    private func mediaPath(named token: String, in directory: URL) -> DetectedPath? {
        let url = directory.appendingPathComponent(token).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let path = pathDetector?.localKind(for: url.path),
              let info = MediaInfo.from(path), info.kind == .image || info.kind == .video
        else { return nil }
        return path
    }

    /// Steps between a match's folder and the selection's folder in the file
    /// tree: the file next to the user is 0, siblings and parents rank close.
    private static func treeDistance(from directory: URL, to file: URL) -> Int {
        let a = directory.pathComponents
        let b = file.deletingLastPathComponent().standardizedFileURL.pathComponents
        let shared = zip(a, b).prefix { $0 == $1 }.count
        return (a.count - shared) + (b.count - shared)
    }

    private func resolveAndShow(selectedText: String,
                                 resolved: [DetectedPath],
                                 tokens: [String],
                                 contextDirectories: [URL] = [],
                                 at anchor: CGPoint,
                                 requestID: UInt64) {
        guard requestID == activeRequestID else { return }
        let uniqueTokens = NSOrderedSet(array: tokens).array as? [String] ?? tokens
        
        // 先显示 loading 面板，让用户知道搜索正在进行
        if let miniAnchor = activeAnchor {
            peekMini?.showLoading(name: uniqueTokens.first ?? "", meta: activeSourceAppName ?? "",
                                  anchor: miniAnchor)
        } else {
            var loadingInfo = MediaInfo(url: URL(fileURLWithPath: "/dev/null"), isLocal: true, kind: .other)
            loadingInfo.searchToken = uniqueTokens.first ?? ""
            self.previewPanel?.showLoading(infos: [loadingInfo], at: anchor)
        }

        // 延迟一帧开始搜索，确保 loading UI 有机会先渲染出来。
        // FileNameResolver.resolve 内部的 quickFilesystemMatches 是同步执行的，
        // 如果在 showLoading 的动画尚未开始前就阻塞主线程，panel 会一直保持
        // alpha = 0，用户就只能等到搜索结束后才看到面板弹出。
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard requestID == self.activeRequestID else { return }

            let group = DispatchGroup()
            var resultsByToken: [String: [FileNameResolver.Match]] = [:]
            for token in uniqueTokens {
                group.enter()
                self.fileNameResolver?.resolve(token: token) { matches in
                    // Closest to any of the selection's folders first; ties keep the resolver's order.
                    func distance(_ url: URL) -> Int {
                        contextDirectories.map { Self.treeDistance(from: $0, to: url) }.min() ?? 0
                    }
                    resultsByToken[token] = matches.enumerated().sorted {
                        let a = distance($0.element.url), b = distance($1.element.url)
                        return a != b ? a < b : $0.offset < $1.offset
                    }.map(\.element)
                    group.leave()
                }
            }
            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                guard requestID == self.activeRequestID else { return }
                // Each selected name means one file: take its best-ranked match
                // (closest to the selection's folder when known).
                let maxFromSpotlight = max(0, 24 - resolved.count)
                let perTokenLimit = 1
                var spotlight: [FileNameResolver.Match] = []
                var cursors = Array(repeating: 0, count: uniqueTokens.count)
                outer: while spotlight.count < maxFromSpotlight {
                    var advanced = false
                    for (i, token) in uniqueTokens.enumerated() {
                        let list = resultsByToken[token] ?? []
                        if cursors[i] < min(list.count, perTokenLimit) {
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
                    self.isLoadingImage = false
                    if self.peekMini?.isVisible == true {
                        self.peekMini?.showFailure(name: label, meta: self.activeSourceAppName ?? "",
                                                   title: "File not found".localized,
                                                   message: self.missingFileMessage(),
                                                   retryTitle: "Search again".localized)
                        PeekDiagnostics.recordMissingFile()
                        return
                    }
                    let failMessage = String(format: "No file found matching '%@'".localized, label)
                    self.previewPanel?.updateTile(at: 0, with: nil, failedMessage: failMessage)
                    PeekDiagnostics.recordMissingFile()
                    self.promptForFullDiskAccessIfNeeded()
                    return
                }

                HistoryManager.shared.record(selectedText: selectedText, detectedPaths: combined)
                if combined.count == 1, self.shouldDirectOpen(combined[0]) {
                    // Same single-hit shortcut as the fast path — close PreviewPanel
                    // so the user only sees ContentPanel.
                    self.previewPanel?.closeWithoutAffectingContent()
                    self.dismissPeekMiniKeepingRequest()
                    self.directOpen(combined[0])
                    return
                }
                let hinted: [String: String] = Dictionary(
                    spotlight.map { ($0.url.absoluteString, Self.disambiguationHint(for: $0.url)) },
                    uniquingKeysWith: { first, _ in first })
                self.loadAndShowMedia(paths: combined, at: anchor, requestID: requestID, hints: hinted)
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
    /// `/Users/me/Desktop/work/Project/img.png` → `~/Desktop/work/Project`.
    /// Truncates to the last 2 components if the tildified path is long.
    private static func disambiguationHint(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().path
        let home = UserHome.path
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
        // Releasing a combo hotkey ends the keyboard gesture, not the Peek.
        // Request and selection state must remain available for the next toggle.
    }

    @objc private func systemDidWake() {
        Logger.info("AppDelegate: System woke from sleep")
        previewPanel?.closePanel()
        previewModeDeactivated()
    }

    private func loadAndShowMedia(paths: [DetectedPath], at position: CGPoint, requestID: UInt64,
                                  hints: [String: String] = [:]) {
        guard requestID == activeRequestID else { return }
        isLoadingImage = true

        errorTooltip?.hide()

        let infos = paths.compactMap { path -> MediaInfo? in
            guard var info = MediaInfo.from(path) else { return nil }
            info.sourceAppName = activeSourceAppName
            info.disambiguationHint = hints[info.url.absoluteString]
            return info
        }
        guard !infos.isEmpty else {
            isLoadingImage = false
            showErrorTooltip(message: "No media to preview".localized, at: position)
            return
        }

        // A hotkey Peek of images or videos opens the small card beside the
        // selection; ↵ there opens the same Inspect the branches below would.
        if let miniAnchor = activeAnchor,
           infos.allSatisfy({ $0.kind == .image || $0.kind == .video }) {
            let mediaPaths = paths.filter {
                guard let kind = MediaInfo.from($0)?.kind else { return false }
                return kind == .image || kind == .video
            }
            previewPanel?.closeWithoutAffectingContent()
            peekMini?.show(paths: mediaPaths, infos: infos, anchor: miniAnchor)
            return
        }

        // Pure image selections use the same full Image Inspect experience as
        // opening image files from Finder. ImageInspectWindow owns its loading
        // pipeline, so it can be shown immediately with empty image slots.
        if infos.allSatisfy({ $0.kind == .image }) {
            let loaded = Array<LoadedMedia?>(repeating: nil, count: infos.count)
            successfulRequestID = requestID
            PeekDiagnostics.recordSuccess(latency: Date().timeIntervalSince(activeRequestStartedAt))
            openImageInspect(infos: infos, loaded: loaded, focusedIndex: 0,
                             preferredMode: Self.preferredInspectMode(for: infos.count))
            return
        }

        // Video selections use the dedicated Inspect window directly: one
        // video opens Focus, while a pair opens Side by Side immediately.
        if infos.allSatisfy({ $0.kind == .video }) {
            successfulRequestID = requestID
            PeekDiagnostics.recordSuccess(latency: Date().timeIntervalSince(activeRequestStartedAt))
            openVideoCompare(infos: infos, focusedIndex: 0)
            return
        }

        // Mixed selections that include any media open in the large Inspect
        // window directly (it previews files inline too); only pure document
        // sets keep the small Preview peek.
        if infos.contains(where: { $0.kind == .image || $0.kind == .video }) {
            let loaded = Array<LoadedMedia?>(repeating: nil, count: infos.count)
            successfulRequestID = requestID
            PeekDiagnostics.recordSuccess(latency: Date().timeIntervalSince(activeRequestStartedAt))
            openImageInspect(infos: infos, loaded: loaded, focusedIndex: 0,
                             preferredMode: infos.count > 1 ? .browse : .focus)
            return
        }

        // Show panel immediately with loading skeletons; populate per-item as
        // the loader streams results back.
        previewPanel?.showLoading(infos: infos, at: position)

        var loadedCount = 0
        imageLoader?.loadMedia(from: paths,
            onProgress: { [weak self] index, media in
                guard let self = self, requestID == self.activeRequestID else { return }
                self.previewPanel?.updateTile(at: index, with: media)
                if media != nil {
                    loadedCount += 1
                    if self.successfulRequestID != requestID {
                        self.successfulRequestID = requestID
                        PeekDiagnostics.recordSuccess(latency: Date().timeIntervalSince(self.activeRequestStartedAt))
                    }
                }
            },
            onComplete: { [weak self] in
                guard let self = self, requestID == self.activeRequestID else { return }
                self.isLoadingImage = false
                Logger.info("AppDelegate: Loaded \(loadedCount)/\(paths.count) media")
                if loadedCount == 0 {
                    Logger.info("AppDelegate: All media failed to load, keeping panel visible with error state")
                    PeekDiagnostics.recordLoadFailure()
                    let needsFDA = paths.contains { path in
                        guard let url = path.url, url.isFileURL else { return false }
                        return self.isUnderProtectedDirectory(url)
                    }
                    if needsFDA && !PermissionManager.shared.isFullDiskAccessGranted {
                        let blocked = paths.lazy.compactMap { $0.url }
                            .first { $0.isFileURL && self.isUnderProtectedDirectory($0) }
                        self.promptForFullDiskAccessIfNeeded(for: blocked)
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
        case .localMarkdown, .remoteMarkdown,
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
        #if MAS
        // In the sandbox every folder the user hasn't granted is protected.
        return !FolderAccess.shared.covers(url.path)
            && !FileManager.default.isReadableFile(atPath: url.path)
        #else
        let path = url.path
        let home = UserHome.path
        let protected = ["/Desktop", "/Documents", "/Downloads", "/Library"]
        return protected.contains { path.hasPrefix(home + $0) }
        #endif
    }

    /// One-hit shortcut: when path detection settles on exactly one file,
    /// bypass the preview panel and perform the same action that clicking
    /// the tile would have triggered.
    private func directOpen(_ path: DetectedPath) {
        guard let info = MediaInfo.from(path) else { return }

        if info.isLocal && isUnderProtectedDirectory(info.url)
            && !PermissionManager.shared.isFullDiskAccessGranted {
            promptForFullDiskAccessIfNeeded(for: info.url)
            return
        }

        Logger.info("AppDelegate: single-hit shortcut → opening \(Logger.redact(info.url.absoluteString))")
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

    private func openImageInspect(infos: [MediaInfo], loaded: [LoadedMedia?], focusedIndex: Int,
                                  preferredMode: ImageInspectSession.Mode? = nil) {
        guard !infos.isEmpty else { return }
        PeekDiagnostics.recordInspectTransition()
        let restoreApp = NSWorkspace.shared.frontmostApplication
        let window = imageInspectWindow ?? ImageInspectWindow(imageLoader: imageLoader ?? ImageLoader())
        imageInspectWindow = window
        window.onOpenVideo = { [weak self] info in
            self?.recordMediaInHistory([info])
            self?.openVideoCompare(infos: [info], focusedIndex: 0)
        }
        window.onOpenContent = { [weak self, weak window] info in
            window?.closeForViewerHandoff()
            self?.openInContentPanel(info: info)
        }
        window.onCaptured = { [weak self, weak window] url in
            self?.openCaptureResult(url: url, source: window)
        }
        window.onClose = { [weak self, weak restoreApp] in
            self?.imageInspectWindow = nil
            if restoreApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                Self.restoreApplication(restoreApp)
            }
        }
        invalidateActiveRequest()
        previewPanel?.closeWithoutAffectingContent()
        window.show(infos: infos, loaded: loaded, focusedIndex: focusedIndex,
                    preferredMode: preferredMode)
    }

    /// Opens a saved capture in its own Image Inspect window, offset from the
    /// window it came from, with a "Capture saved" toast showing the path.
    private func openCaptureResult(url: URL, source: NSWindow?) {
        let window = ImageInspectWindow(imageLoader: imageLoader ?? ImageLoader())
        captureResultWindows.append(window)
        window.onCaptured = { [weak self, weak window] url in
            self?.openCaptureResult(url: url, source: window)
        }
        window.onOpenVideo = { [weak self] info in
            self?.recordMediaInHistory([info])
            self?.openVideoCompare(infos: [info], focusedIndex: 0)
        }
        window.onClose = { [weak self, weak window] in
            guard let window else { return }
            self?.captureResultWindows.removeAll { $0 === window }
        }
        let info = MediaInfo(url: url, isLocal: true, kind: .image)
        window.show(infos: [info], loaded: [nil], focusedIndex: 0, preferredMode: .focus)
        if let origin = source?.frame.origin {
            window.setFrameOrigin(NSPoint(x: origin.x + 28, y: origin.y - 28))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.showToast("Capture saved ✓".localized + "\n" + url.path)
    }

    private func openVideoCompare(infos: [MediaInfo], focusedIndex: Int = 0, startsInCompare: Bool? = nil) {
        guard !infos.isEmpty, infos.allSatisfy({ $0.kind == .video }) else { return }
        previewPanel?.closeWithoutAffectingContent()
        videoCompareWindow?.close()
        let window = VideoCompareWindow(infos: infos, focusedIndex: focusedIndex,
                                        startsInCompare: startsInCompare ?? (infos.count == 2))
        // Clicking a captured-frame thumbnail hands it to Image Inspect:
        // the first opens the window and later clicks append to its filmstrip.
        window?.onCaptureFrame = { [weak self] url in
            self?.openCapturedFrame(url: url)
        }
        window?.onCaptured = { [weak self, weak window] url in
            self?.openCaptureResult(url: url, source: window)
        }
        window?.onOpenImage = { [weak self] info in
            self?.openImageInspect(infos: [info], loaded: [nil], focusedIndex: 0,
                                   preferredMode: .focus)
        }
        videoCompareWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Route a captured video frame into Image Inspect: append to the filmstrip
    /// when a session is open, otherwise open a fresh window.
    private func openCapturedFrame(url: URL) {
        let info = MediaInfo(url: url, isLocal: true, kind: .image)
        if let window = imageInspectWindow, window.isVisible {
            window.appendImage(info: info)
        } else {
            openImageInspect(infos: [info], loaded: [nil], focusedIndex: 0, preferredMode: .focus)
        }
        // The thumbnail is clicked in Video Inspect. Reorder once now
        // and once on the next run-loop turn, after AppKit finishes the source
        // button event, so Video Inspect cannot reclaim the front position.
        NSApp.activate(ignoringOtherApps: true)
        imageInspectWindow?.orderFrontRegardless()
        imageInspectWindow?.makeKey()
        DispatchQueue.main.async { [weak self] in
            self?.imageInspectWindow?.orderFrontRegardless()
            self?.imageInspectWindow?.makeKey()
        }
    }

    private static func preferredInspectMode(for imageCount: Int) -> ImageInspectSession.Mode {
        // Only an exact pair starts in Compare. Larger selections open one
        // focused image with the filmstrip; users choose the pair themselves.
        imageCount == 2 ? .compare : .focus
    }

    private func normalizedSelection(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func restoreApplication(_ application: NSRunningApplication?) {
        guard let application else { return }
        if #available(macOS 14.0, *) {
            application.activate()
        } else {
            application.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func invalidateActiveRequest() {
        activeRequestID &+= 1
        isLoadingImage = false
        currentPath = nil
        activeSelectionText = nil
        activeSourceAppName = nil
        isCheckingVisibleSelection = false
        activeAnchor = nil
        // Keep the source app so we can re-read its current selection. Never
        // retain old selection text: failed reads must not reopen stale files.
    }

    /// PID of the app whose selection should be read. When one of our windows
    /// is frontmost, the remembered source app still owns the selection.
    private func sourceAppPIDForSelection() -> pid_t? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let isGlanceFrontmost = frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier
        if !isGlanceFrontmost, let frontmost {
            lastSourceApp = frontmost
        }
        let pid = isGlanceFrontmost ? lastSourceApp?.processIdentifier : frontmost?.processIdentifier
        return pid.map { pid_t($0) }
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

    // MARK: - Peek Mini

    /// ↵ / click in Peek Mini: the same Inspect a Finder open of these files gets.
    private func openPeekInspect(infos: [MediaInfo], focusedIndex: Int) {
        guard !infos.isEmpty else { return }
        if infos.allSatisfy({ $0.kind == .video }) {
            openVideoCompare(infos: infos, focusedIndex: focusedIndex)
            return
        }
        let mode: ImageInspectSession.Mode = infos.allSatisfy({ $0.kind == .image })
            ? (infos.count == 2 ? .compare : .focus)
            : (infos.count > 1 ? .browse : .focus)
        openImageInspect(infos: infos, loaded: Array(repeating: nil, count: infos.count),
                         focusedIndex: focusedIndex, preferredMode: mode)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func peekMiniDidLoad(succeeded: Bool, paths: [DetectedPath]) {
        isLoadingImage = false
        if succeeded {
            successfulRequestID = activeRequestID
            PeekDiagnostics.recordSuccess(latency: Date().timeIntervalSince(activeRequestStartedAt))
            return
        }
        PeekDiagnostics.recordLoadFailure()
        let blocked = paths.lazy.compactMap { $0.url }.first { $0.isFileURL && self.isUnderProtectedDirectory($0) }
        if let blocked, !PermissionManager.shared.isFullDiskAccessGranted {
            promptForFullDiskAccessIfNeeded(for: blocked)
        }
    }

    /// Closes the card without ending the request that is about to hand off.
    private func dismissPeekMiniKeepingRequest() {
        guard peekMini?.isVisible == true else { return }
        let handler = peekMini?.onDismiss
        peekMini?.onDismiss = nil
        peekMini?.dismiss()
        peekMini?.onDismiss = handler
    }

    /// Body of the "File not found" card: what would let Glance find it.
    private func missingFileMessage() -> String {
        #if MAS
        if !FolderAccess.shared.hasAnyGrant {
            return "Grant Glance access to the folder that contains this file.".localized
        }
        #else
        if !PermissionManager.shared.isFullDiskAccessGranted {
            return "Allow Full Disk Access so Glance can look in Desktop and Documents.".localized
        }
        #endif
        return "Nothing on this Mac has this name. Check the spelling, or select the full path.".localized
    }

    /// Body of the "Can't open this file" card.
    private func unreadableFileMessage(for url: URL?) -> String {
        if let url, url.isFileURL, isUnderProtectedDirectory(url) {
            #if MAS
            return "Grant Glance access to the folder that contains this file.".localized
            #else
            if !PermissionManager.shared.isFullDiskAccessGranted {
                return "Allow Full Disk Access so Glance can look in Desktop and Documents.".localized
            }
            #endif
        }
        if let url, !url.isFileURL {
            return "The download failed. Check your connection, then try again.".localized
        }
        return "The file may have moved, or its format can't be read.".localized
    }

    private func showErrorTooltip(message: String, at position: CGPoint) {
        previewPanel?.hidePanel()
        dismissPeekMiniKeepingRequest()
        errorTooltip?.show(message: message, at: position)
    }

    @objc private func preferencesChanged() {
        if !Preferences.shared.peekEnabled {
            previewModeDeactivated()
        }
        applyPeekState()
        applyTheme()
    }

    /// Reacts only when Peek is switched on or off, not on every preference
    /// change: switching on explains and requests the permissions it needs,
    /// switching off releases the global keyboard tap.
    private func applyPeekState() {
        let enabled = Preferences.shared.peekEnabled
        guard enabled != peekWasEnabled else { return }
        peekWasEnabled = enabled
        if enabled {
            let permissionManager = PermissionManager.shared
            if permissionManager.canUsePeek {
                startKeyboardMonitoring()
            } else {
                showOnboardingWindow()
            }
        } else {
            keyboardMonitor?.stopMonitoring()
        }
    }

    /// The permission guide was dismissed; if Peek is on and the permission
    /// arrived, the hotkey starts working without a relaunch.
    @objc private func onboardingDidClose() {
        adoptPeekIfGrantedFromFirstRunGuide()
        firstRunGuideActive = false
        surfaceHomeIfIdle()
        #if MAS
        FolderAccess.shared.requestOnceIfNeeded()
        #endif
        guard Preferences.shared.peekEnabled, PermissionManager.shared.canUsePeek else { return }
        startKeyboardMonitoring()
    }

    /// First-run guide: Peek stays off unless the user grants Accessibility from
    /// the guide (returning from System Settings or leaving the guide). Skipping
    /// keeps Peek off, and the guide is not offered again.
    private func adoptPeekIfGrantedFromFirstRunGuide() {
        guard firstRunGuideActive, !Preferences.shared.peekEnabled,
              PermissionManager.shared.canUsePeek else { return }
        Logger.info("AppDelegate: Accessibility granted from the first-run guide - enabling Peek")
        Preferences.shared.peekEnabled = true
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func languageChanged() {
        setupMainMenu()
        Logger.info("AppDelegate: Language changed to \(Preferences.shared.appLanguage.rawValue)")
        if let oldWindow = preferencesWindow {
            oldWindow.close()
            preferencesWindow = nil
        }
        // Windows that bake their labels in at construction are discarded so
        // the next open builds them in the new language.
        widgetTaskCenterWindow?.close()
        widgetTaskCenterWindow = nil
        onboardingWindow?.close()
        onboardingWindow = nil
        WidgetMarketPanel.discardForLanguageChange()
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
        // Pin to the theme resolved at launch so system controls match PanelStyle.
        NSApp.appearance = PanelStyle.windowAppearance
    }

    /// Quit and reopen this bundle once the current process has exited.
    static func relaunch() {
        #if MAS
        // The sandbox can't run a shell; ask Launch Services for a fresh copy.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    Logger.error("AppDelegate: Could not relaunch: \(error.localizedDescription)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
        #else
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                          Bundle.main.bundlePath]
        do {
            try task.run()
        } catch {
            Logger.error("AppDelegate: Could not schedule relaunch: \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
        #endif
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
            historyWindow?.onOpenMedia = { [weak self] info in self?.openRecent(info) }
        }
        historyWindow?.refresh()
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openTasks() {
        if widgetTaskCenterWindow == nil { widgetTaskCenterWindow = WidgetTaskCenterWindow() }
        widgetTaskCenterWindow?.refresh()
        widgetTaskCenterWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openHome() {
        if pathDetector == nil || imageLoader == nil { setupComponents() }
        let window = homeWindow ?? makeHomeWindow()
        homeWindow = window
        window.refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeHomeIfVisible() {
        guard let window = homeWindow, window.isVisible else { return }
        window.orderOut(nil)
    }

    private func makeHomeWindow() -> HomeWindow {
        let window = HomeWindow(imageLoader: imageLoader ?? ImageLoader())
        window.onOpenImages = { [weak self] urls in self?.openImages(urls) }
        window.onOpenMedia = { [weak self] urls in self?.openMediaFromHome(urls) }
        window.onOpenFolder = { [weak self] folder in self?.openFolder(folder) }
        window.onOpenRecent = { [weak self] info in self?.openRecent(info) }
        window.onOpenTasks = { [weak self] in self?.openTasks() }
        window.onOpenPreferences = { [weak self] in self?.openPreferences() }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in self?.homeWindow = nil }
        return window
    }

    /// Open a concrete list of local image URLs in Image Inspect.
    private func openImages(_ urls: [URL]) {
        let infos = urls.map { MediaInfo(url: $0, isLocal: $0.isFileURL, kind: .image) }
        guard !infos.isEmpty else { return }
        recordMediaInHistory(infos)
        let loaded = [LoadedMedia?](repeating: nil, count: infos.count)
        let mode = Self.preferredInspectMode(for: infos.count)
        openImageInspect(infos: infos, loaded: loaded, focusedIndex: 0, preferredMode: mode)
        closeHomeIfVisible()
    }

    func openMediaFromHome(_ urls: [URL]) {
        let detector = pathDetector ?? PathDetector()
        let infos = urls.compactMap { MediaInfo.from(detector.localKind(for: $0.path)) }
            .filter { $0.kind == .image || $0.kind == .video }
        guard !infos.isEmpty else { return }
        if infos.allSatisfy({ $0.kind == .image }) {
            openImages(infos.map(\.url))
        } else if infos.allSatisfy({ $0.kind == .video }) {
            recordMediaInHistory(infos)
            openVideoCompare(infos: infos)
            closeHomeIfVisible()
        } else {
            recordMediaInHistory(infos)
            openImageInspect(infos: infos,
                             loaded: Array<LoadedMedia?>(repeating: nil, count: infos.count),
                             focusedIndex: 0, preferredMode: .browse)
            closeHomeIfVisible()
        }
    }

    /// Home, paste, and direct inspection entry points bypass the hotkey
    /// pipeline that normally records history. Persist both images and videos.
    private func recordMediaInHistory(_ infos: [MediaInfo]) {
        let paths: [DetectedPath] = infos.compactMap { info in
            switch info.kind {
            case .image:
                return info.isLocal ? .localImage(info.url.standardizedFileURL) : .remoteImage(info.url)
            case .video:
                return info.isLocal ? .localVideo(info.url.standardizedFileURL) : .remoteVideo(info.url)
            default:
                return nil
            }
        }
        guard !paths.isEmpty else { return }
        HistoryManager.shared.record(selectedText: "", detectedPaths: paths)
    }

    /// Reopen a single recent item, routing by kind the way the preview does.
    private func openRecent(_ info: MediaInfo) {
        switch info.kind {
        case .image:
            recordMediaInHistory([info])
            openImageInspect(infos: [info], loaded: [nil], focusedIndex: 0, preferredMode: .focus)
            closeHomeIfVisible()
        case .video:
            recordMediaInHistory([info])
            openVideoCompare(infos: [info], focusedIndex: 0)
            closeHomeIfVisible()
        case .markdown, .text, .pdf, .webPage:
            openInViewerWindow(info: info)
            closeHomeIfVisible()
        case .other:
            if info.isLocal { NSWorkspace.shared.activateFileViewerSelecting([info.url]) }
            else { NSWorkspace.shared.open(info.url) }
        case .folder:
            openFolder(info.url)
        }
    }

    /// Read every image inside a folder (one level deep) and present them.
    func openFolder(_ folder: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = Self.imageURLs(inFolder: folder)
            DispatchQueue.main.async {
                guard let self = self else { return }
                let window = self.homeWindow ?? self.makeHomeWindow()
                self.homeWindow = window
                window.showFolder(folder, imageURLs: urls)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// List image files directly inside `folder` (non-recursive), sorted by name.
    private static func imageURLs(inFolder folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return entries
            .filter { ImageFormatSupport.supports(extension: $0.pathExtension) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Opens a finished Widget result in Inspect. When the original is still
    /// available it opens alongside the result (original first), with the
    /// result showing; the user enters Compare themselves.
    func openTaskOutputInInspect(_ url: URL) {
        let kind = Self.mediaKind(of: url)
        var infos = [MediaInfo(url: url, isLocal: url.isFileURL, kind: kind)]
        var focusedIndex = 0
        if let source = WidgetTaskManager.shared.sourceURL(forResult: url),
           Self.mediaKind(of: source) == kind,
           !source.isFileURL || FileManager.default.fileExists(atPath: source.path) {
            infos.insert(MediaInfo(url: source, isLocal: source.isFileURL, kind: kind), at: 0)
            focusedIndex = 1
        }
        if kind == .video {
            openVideoCompare(infos: infos, focusedIndex: focusedIndex, startsInCompare: false)
        } else {
            openImageInspect(infos: infos, loaded: Array(repeating: nil, count: infos.count),
                             focusedIndex: focusedIndex, preferredMode: .focus)
        }
    }

    private static func mediaKind(of url: URL) -> MediaInfo.Kind {
        MediaDropCanvasView.videoExtensions.contains(url.pathExtension.lowercased()) ? .video : .image
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Widget-completed banners also show while Glance is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking a "Widget completed" banner opens the result (with its original).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let idString = response.notification.request.content.userInfo["recordID"] as? String,
              let id = UUID(uuidString: idString),
              let output = WidgetTaskManager.shared.records.first(where: { $0.id == id })?.output else { return }
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.openTaskOutputInInspect(output)
        }
    }

    func openLogin(at point: NSPoint) {
        BillingCoordinator.shared.showAccount()
    }


    private func promptForFullDiskAccessIfNeeded(for url: URL? = nil) {
        #if MAS
        // The sandbox has no Full Disk Access: ask for the file's folder, or
        // for any folder when a name search had nothing it could read.
        guard url != nil || !FolderAccess.shared.hasAnyGrant,
              !hasShownFDAAlertThisSession else { return }
        hasShownFDAAlertThisSession = true
        FolderAccess.shared.requestAccess(suggesting: url.map { FolderAccess.suggestedFolder(for: $0.path) })
        #else
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
        #endif
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
