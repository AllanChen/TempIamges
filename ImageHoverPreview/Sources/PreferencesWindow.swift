import AppKit

class PreferencesWindow: NSWindow {
    private var maxSizeSlider: NSSlider!
    private var maxSizeLabel: NSTextField!
    private var enabledCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var readClipboardCheckbox: NSButton!
    private var optionCheckbox: NSButton!
    private var controlCheckbox: NSButton!
    private var currentHotkeyLabel: NSTextField!

    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 460, height: 410)
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
        titleLabel.frame = NSRect(x: 20, y: 360, width: 420, height: 24)
        containerView.addSubview(titleLabel)

        let generalLabel = NSTextField(labelWithString: "General")
        generalLabel.font = NSFont.boldSystemFont(ofSize: 13)
        generalLabel.frame = NSRect(x: 20, y: 320, width: 420, height: 20)
        containerView.addSubview(generalLabel)

        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Image Hover Preview", target: self, action: #selector(enabledToggled))
        enabledCheckbox.frame = NSRect(x: 20, y: 290, width: 300, height: 20)
        containerView.addSubview(enabledCheckbox)

        readClipboardCheckbox = NSButton(checkboxWithTitle: "Read clipboard when no text is selected", target: self, action: #selector(readClipboardToggled))
        readClipboardCheckbox.frame = NSRect(x: 20, y: 260, width: 380, height: 20)
        containerView.addSubview(readClipboardCheckbox)

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

        controlCheckbox = NSButton(checkboxWithTitle: "Control (⌃)", target: self, action: #selector(hotkeyChanged))
        controlCheckbox.frame = NSRect(x: 20, y: 65, width: 140, height: 20)
        containerView.addSubview(controlCheckbox)

        optionCheckbox = NSButton(checkboxWithTitle: "Option (⌥)", target: self, action: #selector(hotkeyChanged))
        optionCheckbox.frame = NSRect(x: 170, y: 65, width: 140, height: 20)
        containerView.addSubview(optionCheckbox)

        currentHotkeyLabel = NSTextField(labelWithString: "")
        currentHotkeyLabel.font = NSFont.systemFont(ofSize: 11)
        currentHotkeyLabel.textColor = .secondaryLabelColor
        currentHotkeyLabel.frame = NSRect(x: 20, y: 42, width: 420, height: 20)
        containerView.addSubview(currentHotkeyLabel)

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
        readClipboardCheckbox.state = prefs.readClipboard ? .on : .off
        launchAtLoginCheckbox.state = prefs.launchAtLogin ? .on : .off
        optionCheckbox.state = prefs.hotkeyRequiresOption ? .on : .off
        controlCheckbox.state = prefs.hotkeyRequiresControl ? .on : .off
        updateCurrentHotkeyLabel()
    }

    private func updateCurrentHotkeyLabel() {
        var parts: [String] = []
        if controlCheckbox.state == .on { parts.append("⌃") }
        if optionCheckbox.state == .on  { parts.append("⌥") }
        currentHotkeyLabel.stringValue = parts.isEmpty
            ? "(no hotkey — preview disabled)"
            : "Current: " + parts.joined(separator: " + ")
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

    @objc private func readClipboardToggled(_ sender: NSButton) {
        Preferences.shared.readClipboard = sender.state == .on
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        Preferences.shared.launchAtLogin = sender.state == .on
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    @objc private func hotkeyChanged(_ sender: NSButton) {
        Preferences.shared.hotkeyRequiresOption = optionCheckbox.state == .on
        Preferences.shared.hotkeyRequiresControl = controlCheckbox.state == .on
        updateCurrentHotkeyLabel()
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
