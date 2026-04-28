import AppKit

class OnboardingWindow: NSWindow {
    private var inputMonitoringStatusLabel: NSTextField!
    private var accessibilityStatusLabel: NSTextField!
    private var continueButton: NSButton!
    private var dontShowAgainCheckbox: NSButton!

    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 480, height: 360)
        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "ImageHoverPreview Needs Permissions"
        self.center()
        self.isReleasedWhenClosed = false

        setupUI()
        updatePermissionStatus()
    }

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        let containerView = NSView(frame: contentView.bounds)
        containerView.autoresizingMask = [.width, .height]
        contentView.addSubview(containerView)

        let titleLabel = NSTextField(labelWithString: "ImageHoverPreview Needs Permissions")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 20, y: 310, width: 440, height: 30)
        containerView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "To enable image previews on hover, please grant the following permissions:")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 20, y: 280, width: 440, height: 20)
        containerView.addSubview(subtitleLabel)

        createInputMonitoringSection(containerView: containerView, y: 200)
        createAccessibilitySection(containerView: containerView, y: 110)

        continueButton = NSButton(title: "Continue", target: self, action: #selector(continuePressed))
        continueButton.bezelStyle = .rounded
        continueButton.frame = NSRect(x: 280, y: 30, width: 100, height: 32)
        continueButton.isEnabled = false
        containerView.addSubview(continueButton)

        dontShowAgainCheckbox = NSButton(checkboxWithTitle: "Don't show again", target: self, action: #selector(dontShowAgainToggled))
        dontShowAgainCheckbox.frame = NSRect(x: 20, y: 35, width: 150, height: 20)
        containerView.addSubview(dontShowAgainCheckbox)
    }

    private func createInputMonitoringSection(containerView: NSView, y: CGFloat) {
        let titleLabel = NSTextField(labelWithString: "Input Monitoring")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: y + 50, width: 200, height: 20)
        containerView.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "Required to detect when you hold Cmd+Shift to activate preview mode.")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = NSColor.secondaryLabelColor
        descLabel.frame = NSRect(x: 20, y: y + 25, width: 350, height: 30)
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.maximumNumberOfLines = 2
        containerView.addSubview(descLabel)

        inputMonitoringStatusLabel = NSTextField(labelWithString: "❌ Not Granted")
        inputMonitoringStatusLabel.font = NSFont.systemFont(ofSize: 12)
        inputMonitoringStatusLabel.frame = NSRect(x: 380, y: y + 50, width: 80, height: 20)
        containerView.addSubview(inputMonitoringStatusLabel)

        let openButton = NSButton(title: "Open Settings", target: self, action: #selector(openInputMonitoringSettings))
        openButton.bezelStyle = .rounded
        openButton.frame = NSRect(x: 380, y: y + 20, width: 80, height: 24)
        containerView.addSubview(openButton)
    }

    private func createAccessibilitySection(containerView: NSView, y: CGFloat) {
        let titleLabel = NSTextField(labelWithString: "Accessibility")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: y + 50, width: 200, height: 20)
        containerView.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "Required to control other applications for image preview functionality.")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = NSColor.secondaryLabelColor
        descLabel.frame = NSRect(x: 20, y: y + 25, width: 350, height: 30)
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.maximumNumberOfLines = 2
        containerView.addSubview(descLabel)

        accessibilityStatusLabel = NSTextField(labelWithString: "❌ Not Granted")
        accessibilityStatusLabel.font = NSFont.systemFont(ofSize: 12)
        accessibilityStatusLabel.frame = NSRect(x: 380, y: y + 50, width: 80, height: 20)
        containerView.addSubview(accessibilityStatusLabel)

        let openButton = NSButton(title: "Open Settings", target: self, action: #selector(openAccessibilitySettings))
        openButton.bezelStyle = .rounded
        openButton.frame = NSRect(x: 380, y: y + 20, width: 80, height: 24)
        containerView.addSubview(openButton)
    }

    private func updatePermissionStatus() {
        let permissionManager = PermissionManager.shared

        if permissionManager.isInputMonitoringGranted {
            inputMonitoringStatusLabel.stringValue = "✅ Granted"
        } else {
            inputMonitoringStatusLabel.stringValue = "❌ Not Granted"
        }

        if permissionManager.isAccessibilityGranted {
            accessibilityStatusLabel.stringValue = "✅ Granted"
        } else {
            accessibilityStatusLabel.stringValue = "❌ Not Granted"
        }

        continueButton.isEnabled = permissionManager.isInputMonitoringGranted && permissionManager.isAccessibilityGranted
    }

    @objc private func openInputMonitoringSettings() {
        PermissionManager.shared.openInputMonitoringSettings()
        startPermissionPolling()
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.shared.openAccessibilitySettings()
        startPermissionPolling()
    }

    private var permissionCheckTimer: Timer?

    private func startPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePermissionStatus()
        }
    }

    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    deinit {
        stopPermissionPolling()
    }

    @objc private func continuePressed() {
        UserDefaults.standard.set(true, forKey: "dontShowOnboardingAgain")
        stopPermissionPolling()
        self.close()
    }

    @objc private func dontShowAgainToggled() {
        UserDefaults.standard.set(dontShowAgainCheckbox.state == .on, forKey: "dontShowOnboardingAgain")
    }

    func refreshPermissionStatus() {
        updatePermissionStatus()
    }
}