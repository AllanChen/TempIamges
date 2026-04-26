import AppKit

class PreferencesWindow: NSWindow {
    private var maxSizeSlider: NSSlider!
    private var maxSizeLabel: NSTextField!
    private var enabledCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var cmdCheckbox: NSButton!
    private var shiftCheckbox: NSButton!

    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 460, height: 380)
        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "Preferences"
        self.center()
        self.isReleasedWhenClosed = false

        setupUI()
        loadSettings()
    }

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        let containerView = NSView(frame: contentView.bounds)
        containerView.autoresizingMask = [.width, .height]
        contentView.addSubview(containerView)

        let titleLabel = NSTextField(labelWithString: "ImageHoverPreview Preferences")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 20, y: 330, width: 420, height: 24)
        containerView.addSubview(titleLabel)

        let generalLabel = NSTextField(labelWithString: "General")
        generalLabel.font = NSFont.boldSystemFont(ofSize: 13)
        generalLabel.frame = NSRect(x: 20, y: 290, width: 420, height: 20)
        containerView.addSubview(generalLabel)

        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Image Hover Preview", target: self, action: #selector(enabledToggled))
        enabledCheckbox.frame = NSRect(x: 20, y: 260, width: 300, height: 20)
        containerView.addSubview(enabledCheckbox)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(launchAtLoginToggled))
        launchAtLoginCheckbox.frame = NSRect(x: 20, y: 230, width: 300, height: 20)
        containerView.addSubview(launchAtLoginCheckbox)

        // Max preview size section
        let sizeLabel = NSTextField(labelWithString: "Maximum Preview Size")
        sizeLabel.font = NSFont.boldSystemFont(ofSize: 13)
        sizeLabel.frame = NSRect(x: 20, y: 190, width: 200, height: 20)
        containerView.addSubview(sizeLabel)

        maxSizeSlider = NSSlider(value: 400, minValue: 200, maxValue: 800, target: self, action: #selector(maxSizeChanged))
        maxSizeSlider.frame = NSRect(x: 20, y: 160, width: 300, height: 20)
        maxSizeSlider.numberOfTickMarks = 7
        maxSizeSlider.allowsTickMarkValuesOnly = false
        containerView.addSubview(maxSizeSlider)

        maxSizeLabel = NSTextField(labelWithString: "400 px")
        maxSizeLabel.font = NSFont.systemFont(ofSize: 12)
        maxSizeLabel.textColor = .secondaryLabelColor
        maxSizeLabel.frame = NSRect(x: 330, y: 160, width: 80, height: 20)
        containerView.addSubview(maxSizeLabel)

        // Hotkey section
        let hotkeyLabel = NSTextField(labelWithString: "Activation Hotkey")
        hotkeyLabel.font = NSFont.boldSystemFont(ofSize: 13)
        hotkeyLabel.frame = NSRect(x: 20, y: 120, width: 200, height: 20)
        containerView.addSubview(hotkeyLabel)

        let hotkeyDesc = NSTextField(labelWithString: "Hold these keys while hovering to show previews:")
        hotkeyDesc.font = NSFont.systemFont(ofSize: 12)
        hotkeyDesc.textColor = .secondaryLabelColor
        hotkeyDesc.frame = NSRect(x: 20, y: 95, width: 400, height: 20)
        containerView.addSubview(hotkeyDesc)

        cmdCheckbox = NSButton(checkboxWithTitle: "Command (⌘)", target: self, action: #selector(hotkeyChanged))
        cmdCheckbox.frame = NSRect(x: 20, y: 65, width: 140, height: 20)
        containerView.addSubview(cmdCheckbox)

        shiftCheckbox = NSButton(checkboxWithTitle: "Shift (⇧)", target: self, action: #selector(hotkeyChanged))
        shiftCheckbox.frame = NSRect(x: 170, y: 65, width: 140, height: 20)
        containerView.addSubview(shiftCheckbox)

        // Reset button
        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 20, y: 20, width: 140, height: 28)
        containerView.addSubview(resetButton)
    }

    private func loadSettings() {
        let prefs = Preferences.shared
        maxSizeSlider.doubleValue = Double(prefs.maxPreviewSize)
        maxSizeLabel.stringValue = "\(Int(prefs.maxPreviewSize)) px"
        enabledCheckbox.state = prefs.enabled ? .on : .off
        launchAtLoginCheckbox.state = prefs.launchAtLogin ? .on : .off
        cmdCheckbox.state = prefs.hotkeyRequiresCommand ? .on : .off
        shiftCheckbox.state = prefs.hotkeyRequiresShift ? .on : .off
    }

    @objc private func maxSizeChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        maxSizeLabel.stringValue = "\(Int(value)) px"
        Preferences.shared.maxPreviewSize = value
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func enabledToggled(_ sender: NSButton) {
        Preferences.shared.enabled = sender.state == .on
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        Preferences.shared.launchAtLogin = sender.state == .on
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func hotkeyChanged(_ sender: NSButton) {
        Preferences.shared.hotkeyRequiresCommand = cmdCheckbox.state == .on
        Preferences.shared.hotkeyRequiresShift = shiftCheckbox.state == .on
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func resetToDefaults() {
        Preferences.shared.resetToDefaults()
        loadSettings()
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("Preferences.preferencesDidChange")
}
