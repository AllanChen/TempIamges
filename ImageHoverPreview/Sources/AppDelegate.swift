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

        // Anchor preview just below the selection's bottom-left when AX gives
        // us bounds; otherwise fall back to the mouse position (clipboard
        // fallback path for non-AX apps).
        let anchor: CGPoint
        if let bounds = result.bounds {
            anchor = CGPoint(x: bounds.minX, y: bounds.maxY)
        } else {
            anchor = mousePos
        }

        let urls = (pathDetector?.detectAll(selected) ?? []).compactMap { $0.url }
        guard !urls.isEmpty else {
            Logger.info("AppDelegate: No image path in selected text")
            currentPath = selected
            showErrorTooltip(message: "No image found in selection", at: anchor)
            return
        }

        Logger.info("AppDelegate: Loading \(urls.count) image(s) from selection")
        currentPath = urls.map { $0.absoluteString }.joined(separator: "|")
        loadAndShowImages(urls: urls, at: anchor)
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
        currentPath = nil
        isLoadingImage = false
    }

    private func loadAndShowImages(urls: [URL], at position: CGPoint) {
        guard !isLoadingImage else { return }
        isLoadingImage = true

        errorTooltip?.hide()

        imageLoader?.loadImages(from: urls) { [weak self] images in
            self?.isLoadingImage = false
            guard let self = self else { return }

            let valid = images.compactMap { $0 }
            if valid.isEmpty {
                Logger.info("AppDelegate: All \(urls.count) images failed to load")
                self.showErrorTooltip(message: "Failed to load image", at: position)
                return
            }
            Logger.info("AppDelegate: Loaded \(valid.count)/\(urls.count) image(s), showing preview")
            self.previewPanel?.showImages(valid, at: position)
        }
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
