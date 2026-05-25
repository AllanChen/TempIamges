import AppKit

class OnboardingWindow: NSWindow {
    private var inputMonitoringStatusView: PermissionStatusView!
    private var accessibilityStatusView: PermissionStatusView!
    private var fullDiskAccessStatusView: PermissionStatusView!
    private var continueButton: NSButton!
    private var dontShowAgainCheckbox: NSButton!

    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 560, height: 600)
        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "Welcome to Glance".localized
        self.center()
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false

        setupUI()
        updatePermissionStatus()
    }

    private func setupUI() {
        guard let contentView = self.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let iconSize: CGFloat = 64
        let iconView = NSImageView(frame: NSRect(
            x: (contentView.bounds.width - iconSize) / 2,
            y: contentView.bounds.height - 100,
            width: iconSize,
            height: iconSize
        ))
        iconView.image = NSImage(named: NSImage.applicationIconName)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "Welcome to Glance!".localized)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 22)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: contentView.bounds.height - 140, width: contentView.bounds.width - 40, height: 30)
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Before you can start previewing, we need to ask you for a few permissions.".localized)
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.frame = NSRect(x: 40, y: contentView.bounds.height - 170, width: contentView.bounds.width - 80, height: 20)
        contentView.addSubview(subtitleLabel)

        let itemWidth: CGFloat = contentView.bounds.width - 80
        let itemX: CGFloat = 40
        var currentY = contentView.bounds.height - 220

        inputMonitoringStatusView = PermissionStatusView(
            title: "Input Monitoring Permission".localized,
            description: "Glance needs to detect when you hold the hotkey to activate preview mode.".localized,
            isRequired: true
        )
        inputMonitoringStatusView.target = self
        inputMonitoringStatusView.openSettingsAction = #selector(openInputMonitoringSettings)
        inputMonitoringStatusView.frame = NSRect(x: itemX, y: currentY - 70, width: itemWidth, height: 70)
        contentView.addSubview(inputMonitoringStatusView)
        currentY -= 100

        accessibilityStatusView = PermissionStatusView(
            title: "Accessibility Permission".localized,
            description: "Glance needs to read the selected text in the active app so we know what to preview.".localized,
            isRequired: true
        )
        accessibilityStatusView.target = self
        accessibilityStatusView.openSettingsAction = #selector(openAccessibilitySettings)
        accessibilityStatusView.frame = NSRect(x: itemX, y: currentY - 70, width: itemWidth, height: 70)
        contentView.addSubview(accessibilityStatusView)
        currentY -= 100

        fullDiskAccessStatusView = PermissionStatusView(
            title: "Full Disk Access Permission".localized,
            description: "Optional — lets the app preview files in Desktop / Documents / iCloud without per-folder prompts.".localized,
            isRequired: false
        )
        fullDiskAccessStatusView.target = self
        fullDiskAccessStatusView.openSettingsAction = #selector(openFullDiskAccessSettings)
        fullDiskAccessStatusView.frame = NSRect(x: itemX, y: currentY - 70, width: itemWidth, height: 70)
        contentView.addSubview(fullDiskAccessStatusView)
        currentY -= 100

        dontShowAgainCheckbox = NSButton(checkboxWithTitle: "Don't show again".localized, target: self, action: #selector(dontShowAgainToggled))
        dontShowAgainCheckbox.frame = NSRect(x: 40, y: 60, width: 150, height: 20)
        contentView.addSubview(dontShowAgainCheckbox)

        continueButton = NSButton(title: "Continue".localized, target: self, action: #selector(continuePressed))
        continueButton.bezelStyle = .rounded
        continueButton.frame = NSRect(x: contentView.bounds.width - 160, y: 55, width: 120, height: 32)
        continueButton.isEnabled = false
        contentView.addSubview(continueButton)
    }

    private func updatePermissionStatus() {
        let permissionManager = PermissionManager.shared

        let inputMonitoringGranted = permissionManager.isInputMonitoringGranted
        let accessibilityGranted = permissionManager.isAccessibilityGranted
        let fullDiskAccessGranted = permissionManager.isFullDiskAccessGranted

        inputMonitoringStatusView.updateStatus(granted: inputMonitoringGranted)
        accessibilityStatusView.updateStatus(granted: accessibilityGranted)
        fullDiskAccessStatusView.updateStatus(granted: fullDiskAccessGranted)

        continueButton.isEnabled = inputMonitoringGranted && accessibilityGranted
    }

    @objc private func openInputMonitoringSettings() {
        PermissionManager.shared.openInputMonitoringSettings()
        startPermissionPolling()
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.shared.openAccessibilitySettings()
        startPermissionPolling()
    }

    @objc private func openFullDiskAccessSettings() {
        PermissionManager.shared.openFullDiskAccessSettings()
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

class PermissionStatusView: NSView {
    var openSettingsAction: Selector?
    weak var target: AnyObject?

    private let titleLabel = NSTextField()
    private let descLabel = NSTextField()
    private let statusContainer = NSView()
    private let statusIcon = NSTextField()
    private let statusLabel = NSTextField()
    private let openSettingsButton = NSButton()
    private var isRequired = true

    init(title: String, description: String, isRequired: Bool) {
        self.isRequired = isRequired
        super.init(frame: .zero)
        setupViews(title: title, description: description)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(title: String, description: String) {
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.stringValue = title
        titleLabel.frame = NSRect(x: 0, y: 45, width: 320, height: 20)
        addSubview(titleLabel)

        descLabel.isEditable = false
        descLabel.isBordered = false
        descLabel.backgroundColor = .clear
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.stringValue = description
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.maximumNumberOfLines = 2
        descLabel.frame = NSRect(x: 0, y: 0, width: 320, height: 40)
        addSubview(descLabel)

        statusContainer.wantsLayer = true
        statusContainer.layer?.cornerRadius = 6
        statusContainer.layer?.borderWidth = 1
        statusContainer.frame = NSRect(x: 340, y: 20, width: 180, height: 36)
        addSubview(statusContainer)

        statusIcon.isEditable = false
        statusIcon.isBordered = false
        statusIcon.backgroundColor = .clear
        statusIcon.font = NSFont.systemFont(ofSize: 14)
        statusIcon.alignment = .center
        statusIcon.frame = NSRect(x: 8, y: 0, width: 20, height: 36)
        statusContainer.addSubview(statusIcon)

        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.alignment = .left
        statusLabel.frame = NSRect(x: 28, y: 0, width: 144, height: 36)
        statusContainer.addSubview(statusLabel)

        openSettingsButton.title = "Open Settings".localized
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.font = NSFont.systemFont(ofSize: 11)
        openSettingsButton.frame = NSRect(x: 340, y: 20, width: 180, height: 28)
        openSettingsButton.target = self
        openSettingsButton.action = #selector(settingsButtonClicked)
        addSubview(openSettingsButton)
    }

    func updateStatus(granted: Bool) {
        if granted {
            statusContainer.isHidden = false
            statusIcon.isHidden = false
            statusLabel.isHidden = false
            openSettingsButton.isHidden = true

            statusIcon.stringValue = "✓"
            statusIcon.textColor = NSColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)
            statusLabel.stringValue = "Enabled".localized
            statusLabel.textColor = NSColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)
            statusContainer.layer?.backgroundColor = NSColor(red: 0.15, green: 0.35, blue: 0.2, alpha: 0.3).cgColor
            statusContainer.layer?.borderColor = NSColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 0.5).cgColor
        } else {
            statusContainer.isHidden = true
            statusIcon.isHidden = true
            statusLabel.isHidden = true
            openSettingsButton.isHidden = false
        }
    }

    @objc private func settingsButtonClicked() {
        if let target = target, let action = openSettingsAction {
            _ = target.perform(action, with: nil)
        }
    }
}
