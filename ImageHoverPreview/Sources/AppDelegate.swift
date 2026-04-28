import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, StatusBarControllerDelegate {
    private var statusBarController: StatusBarController?
    private var keyboardMonitor: KeyboardMonitor?
    private var mouseTracker: MouseTracker?
    private var textExtractor: TextExtractor?
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
        mouseTracker?.stopTracking()
    }

    private func setupComponents() {
        statusBarController = StatusBarController()
        statusBarController?.delegate = self

        keyboardMonitor = KeyboardMonitor()
        mouseTracker = MouseTracker()
        textExtractor = TextExtractor()
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
            selector: #selector(mousePositionChanged),
            name: MouseTracker.mousePositionDidChange,
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
        onboardingWindow = OnboardingWindow()
        onboardingWindow?.makeKeyAndOrderFront(nil)
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

        mouseTracker?.startTracking()
        textExtractor?.reset()
        Logger.info("AppDelegate: Mouse tracking started")
    }

    @objc private func previewModeDeactivated() {
        Logger.info("AppDelegate: Preview mode deactivated")
        mouseTracker?.stopTracking()
        previewPanel?.hidePanel()
        errorTooltip?.hide()
        textExtractor?.reset()
        currentPath = nil
        isLoadingImage = false
    }

    @objc private func mousePositionChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let position = userInfo["position"] as? CGPoint else {
            return
        }

        processMousePosition(position)
    }

    private func processMousePosition(_ position: CGPoint) {
        Logger.info("AppDelegate: Processing mouse position (\(position.x), \(position.y))")
        
        guard let extractedText = textExtractor?.extractText(at: position, debounce: true) else {
            Logger.info("AppDelegate: No text extracted")
            hideAllPanels()
            return
        }

        Logger.info("AppDelegate: Extracted text='\(extractedText)'")
        
        let detectedPath = pathDetector?.detect(extractedText)

        switch detectedPath {
        case .localImage(let url), .remoteImage(let url):
            let pathString = url.absoluteString
            Logger.info("AppDelegate: Detected image path='\(pathString)'")
            if pathString != currentPath {
                currentPath = pathString
                loadAndShowImage(url: url, at: position)
            }
        case .invalid, .none:
            Logger.info("AppDelegate: No valid image path detected")
            if extractedText != currentPath {
                currentPath = extractedText
                showErrorTooltip(message: "No image found", at: position)
            }
        }
    }

    private func loadAndShowImage(url: URL, at position: CGPoint) {
        guard !isLoadingImage else { return }
        isLoadingImage = true

        errorTooltip?.hide()
        
        Logger.info("AppDelegate: Loading image from '\(url.absoluteString)'")

        imageLoader?.loadImage(from: url) { [weak self] image in
            self?.isLoadingImage = false

            guard let self = self else { return }

            if let image = image {
                Logger.info("AppDelegate: Image loaded successfully, showing preview")
                self.previewPanel?.showImage(image, at: position)
            } else {
                Logger.info("AppDelegate: Failed to load image")
                self.showErrorTooltip(message: "Failed to load image", at: position)
            }
        }
    }

    private func showErrorTooltip(message: String, at position: CGPoint) {
        previewPanel?.hidePanel()
        errorTooltip?.show(message: message, at: position)
    }

    private func hideAllPanels() {
        previewPanel?.hidePanel()
        errorTooltip?.hide()
        currentPath = nil
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
