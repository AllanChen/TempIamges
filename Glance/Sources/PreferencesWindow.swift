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
    private var languagePopup: NSPopUpButton!

    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 460, height: 455)
        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "Preferences".localized
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

        let titleLabel = NSTextField(labelWithString: "Glance Preferences".localized)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 20, y: 415, width: 420, height: 24)
        containerView.addSubview(titleLabel)

        let languageLabel = NSTextField(labelWithString: "Language".localized)
        languageLabel.font = NSFont.boldSystemFont(ofSize: 13)
        languageLabel.frame = NSRect(x: 20, y: 385, width: 200, height: 20)
        containerView.addSubview(languageLabel)

        languagePopup = NSPopUpButton(frame: NSRect(x: 20, y: 360, width: 200, height: 24), pullsDown: false)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        for lang in Preferences.AppLanguage.allCases {
            languagePopup.addItem(withTitle: lang.displayName)
            languagePopup.lastItem?.representedObject = lang.rawValue
        }
        containerView.addSubview(languagePopup)

        let generalLabel = NSTextField(labelWithString: "General".localized)
        generalLabel.font = NSFont.boldSystemFont(ofSize: 13)
        generalLabel.frame = NSRect(x: 20, y: 330, width: 420, height: 20)
        containerView.addSubview(generalLabel)

        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Image Hover Preview".localized, target: self, action: #selector(enabledToggled))
        enabledCheckbox.frame = NSRect(x: 20, y: 300, width: 300, height: 20)
        containerView.addSubview(enabledCheckbox)

        readClipboardCheckbox = NSButton(checkboxWithTitle: "Read clipboard when no text is selected".localized, target: self, action: #selector(readClipboardToggled))
        readClipboardCheckbox.frame = NSRect(x: 20, y: 270, width: 380, height: 20)
        containerView.addSubview(readClipboardCheckbox)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login".localized, target: self, action: #selector(launchAtLoginToggled))
        launchAtLoginCheckbox.frame = NSRect(x: 20, y: 240, width: 300, height: 20)
        containerView.addSubview(launchAtLoginCheckbox)

        let sizeLabel = NSTextField(labelWithString: "Maximum Preview Size".localized)
        sizeLabel.font = NSFont.boldSystemFont(ofSize: 13)
        sizeLabel.frame = NSRect(x: 20, y: 200, width: 200, height: 20)
        containerView.addSubview(sizeLabel)

        maxSizeSlider = NSSlider(value: 400, minValue: 200, maxValue: 800, target: self, action: #selector(maxSizeChanged))
        maxSizeSlider.frame = NSRect(x: 20, y: 170, width: 300, height: 20)
        maxSizeSlider.numberOfTickMarks = 7
        maxSizeSlider.allowsTickMarkValuesOnly = false
        containerView.addSubview(maxSizeSlider)

        maxSizeLabel = NSTextField(labelWithString: String(format: "%d px".localized, Int(Preferences.shared.maxPreviewSize)))
        maxSizeLabel.font = NSFont.systemFont(ofSize: 12)
        maxSizeLabel.textColor = .secondaryLabelColor
        maxSizeLabel.frame = NSRect(x: 330, y: 170, width: 80, height: 20)
        containerView.addSubview(maxSizeLabel)

        let hotkeyLabel = NSTextField(labelWithString: "Activation Hotkey".localized)
        hotkeyLabel.font = NSFont.boldSystemFont(ofSize: 13)
        hotkeyLabel.frame = NSRect(x: 20, y: 130, width: 200, height: 20)
        containerView.addSubview(hotkeyLabel)

        let hotkeyDesc = NSTextField(labelWithString: "Hold these keys while hovering to show previews:".localized)
        hotkeyDesc.font = NSFont.systemFont(ofSize: 12)
        hotkeyDesc.textColor = .secondaryLabelColor
        hotkeyDesc.frame = NSRect(x: 20, y: 105, width: 400, height: 20)
        containerView.addSubview(hotkeyDesc)

        controlCheckbox = NSButton(checkboxWithTitle: "Control (⌃)".localized, target: self, action: #selector(hotkeyChanged))
        controlCheckbox.frame = NSRect(x: 20, y: 75, width: 140, height: 20)
        containerView.addSubview(controlCheckbox)

        optionCheckbox = NSButton(checkboxWithTitle: "Option (⌥)".localized, target: self, action: #selector(hotkeyChanged))
        optionCheckbox.frame = NSRect(x: 170, y: 75, width: 140, height: 20)
        containerView.addSubview(optionCheckbox)

        currentHotkeyLabel = NSTextField(labelWithString: "")
        currentHotkeyLabel.font = NSFont.systemFont(ofSize: 11)
        currentHotkeyLabel.textColor = .secondaryLabelColor
        currentHotkeyLabel.frame = NSRect(x: 20, y: 50, width: 420, height: 20)
        containerView.addSubview(currentHotkeyLabel)

        let resetButton = NSButton(title: "Reset to Defaults".localized, target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 20, y: 15, width: 140, height: 28)
        containerView.addSubview(resetButton)
    }

    private func loadSettings() {
        let prefs = Preferences.shared
        maxSizeSlider.doubleValue = Double(prefs.maxPreviewSize)
        maxSizeLabel.stringValue = String(format: "%d px".localized, Int(prefs.maxPreviewSize))
        enabledCheckbox.state = prefs.enabled ? .on : .off
        readClipboardCheckbox.state = prefs.readClipboard ? .on : .off
        launchAtLoginCheckbox.state = prefs.launchAtLogin ? .on : .off
        optionCheckbox.state = prefs.hotkeyRequiresOption ? .on : .off
        controlCheckbox.state = prefs.hotkeyRequiresControl ? .on : .off
        updateCurrentHotkeyLabel()
        updateLanguagePopup()
    }

    private func updateLanguagePopup() {
        let current = Preferences.shared.appLanguage.rawValue
        for (index, item) in languagePopup.itemArray.enumerated() {
            if (item.representedObject as? String) == current {
                languagePopup.selectItem(at: index)
                break
            }
        }
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let lang = Preferences.AppLanguage(rawValue: raw),
              lang != Preferences.shared.appLanguage else { return }

        Preferences.shared.appLanguage = lang
        LanguageService.invalidateCache()

        let alert = NSAlert()
        alert.messageText = "Language Changed".localized
        alert.informativeText = "The language has been updated.".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK".localized)
        alert.runModal()

        NotificationCenter.default.post(name: .languageDidChange, object: self)
    }

    private func updateCurrentHotkeyLabel() {
        var parts: [String] = []
        if controlCheckbox.state == .on { parts.append("⌃") }
        if optionCheckbox.state == .on  { parts.append("⌥") }
        currentHotkeyLabel.stringValue = parts.isEmpty
            ? "(no hotkey — preview disabled)".localized
            : "Current: ".localized + parts.joined(separator: " + ")
    }

    @objc private func maxSizeChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        maxSizeLabel.stringValue = String(format: "%d px".localized, Int(value))
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
    static let languageDidChange = Notification.Name("Preferences.languageDidChange")
}
