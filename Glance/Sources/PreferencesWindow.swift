import AppKit

protocol ShortcutRecorderDelegate: AnyObject {
    func shortcutRecorderDidBeginRecording(_ recorder: ShortcutRecorderField)
    func shortcutRecorder(_ recorder: ShortcutRecorderField, didRecordModifiers modifiers: NSEvent.ModifierFlags)
    func shortcutRecorderDidEndRecording(_ recorder: ShortcutRecorderField)
    func shortcutRecorderDidCancelRecording(_ recorder: ShortcutRecorderField)
}

final class ShortcutRecorderField: NSTextField {
    weak var recorderDelegate: ShortcutRecorderDelegate?
    private(set) var isRecording: Bool = false

    override var acceptsFirstResponder: Bool { isRecording }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        window?.makeFirstResponder(self)
        recorderDelegate?.shortcutRecorderDidBeginRecording(self)
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        window?.makeFirstResponder(nil)
        recorderDelegate?.shortcutRecorderDidEndRecording(self)
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        window?.makeFirstResponder(nil)
        recorderDelegate?.shortcutRecorderDidCancelRecording(self)
    }

    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            beginRecording()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        recorderDelegate?.shortcutRecorder(self, didRecordModifiers: mods)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 {
            cancelRecording()
        }
    }
}

class PreferencesWindow: NSWindow, ShortcutRecorderDelegate {
    private var enabledCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var readClipboardCheckbox: NSButton!
    private var modePopup: NSPopUpButton!
    private var customShortcutField: ShortcutRecorderField!
    private var currentHotkeyLabel: NSTextField!
    private var languagePopup: NSPopUpButton!
    private var recordedModifiers: NSEvent.ModifierFlags = []

    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 460, height: 360)
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
        titleLabel.frame = NSRect(x: 20, y: 320, width: 420, height: 24)
        containerView.addSubview(titleLabel)

        let languageLabel = NSTextField(labelWithString: "Language".localized)
        languageLabel.font = NSFont.boldSystemFont(ofSize: 13)
        languageLabel.frame = NSRect(x: 20, y: 290, width: 200, height: 20)
        containerView.addSubview(languageLabel)

        languagePopup = NSPopUpButton(frame: NSRect(x: 20, y: 265, width: 200, height: 24), pullsDown: false)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        for lang in Preferences.AppLanguage.allCases {
            languagePopup.addItem(withTitle: lang.displayName)
            languagePopup.lastItem?.representedObject = lang.rawValue
        }
        containerView.addSubview(languagePopup)

        let generalLabel = NSTextField(labelWithString: "General".localized)
        generalLabel.font = NSFont.boldSystemFont(ofSize: 13)
        generalLabel.frame = NSRect(x: 20, y: 235, width: 420, height: 20)
        containerView.addSubview(generalLabel)

        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Image Hover Preview".localized, target: self, action: #selector(enabledToggled))
        enabledCheckbox.frame = NSRect(x: 20, y: 205, width: 300, height: 20)
        containerView.addSubview(enabledCheckbox)

        readClipboardCheckbox = NSButton(checkboxWithTitle: "Read clipboard when no text is selected".localized, target: self, action: #selector(readClipboardToggled))
        readClipboardCheckbox.frame = NSRect(x: 20, y: 175, width: 380, height: 20)
        containerView.addSubview(readClipboardCheckbox)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login".localized, target: self, action: #selector(launchAtLoginToggled))
        launchAtLoginCheckbox.frame = NSRect(x: 20, y: 145, width: 300, height: 20)
        containerView.addSubview(launchAtLoginCheckbox)

        let hotkeyLabel = NSTextField(labelWithString: "Activation Hotkey".localized)
        hotkeyLabel.font = NSFont.boldSystemFont(ofSize: 13)
        hotkeyLabel.frame = NSRect(x: 20, y: 105, width: 200, height: 20)
        containerView.addSubview(hotkeyLabel)

        let hotkeyDesc = NSTextField(labelWithString: "Hold these keys while hovering to show previews:".localized)
        hotkeyDesc.font = NSFont.systemFont(ofSize: 12)
        hotkeyDesc.textColor = .secondaryLabelColor
        hotkeyDesc.frame = NSRect(x: 20, y: 80, width: 400, height: 20)
        containerView.addSubview(hotkeyDesc)

        modePopup = NSPopUpButton(frame: NSRect(x: 20, y: 50, width: 160, height: 24), pullsDown: false)
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        for m in Preferences.ActivationMode.allCases {
            modePopup.addItem(withTitle: m.displayName.localized)
            modePopup.lastItem?.representedObject = m.rawValue
        }
        containerView.addSubview(modePopup)

        customShortcutField = ShortcutRecorderField(frame: NSRect(x: 190, y: 50, width: 200, height: 24))
        customShortcutField.isEditable = false
        customShortcutField.isSelectable = false
        customShortcutField.alignment = .center
        customShortcutField.isBordered = true
        customShortcutField.backgroundColor = .textBackgroundColor
        customShortcutField.font = NSFont.systemFont(ofSize: 13)
        customShortcutField.placeholderString = "Click to record shortcut".localized
        customShortcutField.recorderDelegate = self
        containerView.addSubview(customShortcutField)

        currentHotkeyLabel = NSTextField(labelWithString: "")
        currentHotkeyLabel.font = NSFont.systemFont(ofSize: 11)
        currentHotkeyLabel.textColor = .secondaryLabelColor
        currentHotkeyLabel.frame = NSRect(x: 20, y: 21, width: 420, height: 20)
        containerView.addSubview(currentHotkeyLabel)

        let resetButton = NSButton(title: "Reset to Defaults".localized, target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 20, y: 15, width: 140, height: 28)
        containerView.addSubview(resetButton)
    }

    private func loadSettings() {
        let prefs = Preferences.shared
        enabledCheckbox.state = prefs.enabled ? .on : .off
        readClipboardCheckbox.state = prefs.readClipboard ? .on : .off
        launchAtLoginCheckbox.state = prefs.launchAtLogin ? .on : .off
        updateModePopup()
        updateHotkeyUI()
        updateLanguagePopup()
    }

    private func updateModePopup() {
        let current = Preferences.shared.activationMode.rawValue
        for (index, item) in modePopup.itemArray.enumerated() {
            if (item.representedObject as? String) == current {
                modePopup.selectItem(at: index)
                break
            }
        }
    }

    private func updateHotkeyUI() {
        let prefs = Preferences.shared
        let isCustom = prefs.activationMode == .custom
        customShortcutField.isHidden = !isCustom
        if isCustom {
            let mods = prefs.customHotkeyModifiers
            customShortcutField.stringValue = modifierString(mods)
        customShortcutField.placeholderString = "Click to record shortcut".localized
        }
        updateCurrentHotkeyLabel()
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
        let modifiers = Preferences.shared.effectiveModifiers
        let symbol = modifierString(modifiers)
        currentHotkeyLabel.stringValue = symbol.isEmpty
            ? "(no hotkey — preview disabled)".localized
            : "Current: ".localized + symbol
    }

    private func modifierString(_ modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        return parts.joined(separator: " + ")
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let mode = Preferences.ActivationMode(rawValue: raw) else { return }
        Preferences.shared.activationMode = mode
        updateHotkeyUI()
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    func shortcutRecorderDidBeginRecording(_ recorder: ShortcutRecorderField) {
        recordedModifiers = []
        customShortcutField.stringValue = ""
        customShortcutField.placeholderString = "Press shortcut...".localized
        customShortcutField.textColor = .systemBlue
    }

    func shortcutRecorder(_ recorder: ShortcutRecorderField, didRecordModifiers modifiers: NSEvent.ModifierFlags) {
        if modifiers.isEmpty {
            if !recordedModifiers.isEmpty {
                recorder.endRecording()
            }
        } else {
            recordedModifiers = recordedModifiers.union(modifiers)
            customShortcutField.stringValue = modifierString(recordedModifiers)
        }
    }

    func shortcutRecorderDidEndRecording(_ recorder: ShortcutRecorderField) {
        Preferences.shared.customHotkeyModifiers = recordedModifiers
        customShortcutField.textColor = .labelColor
        updateHotkeyUI()
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    func shortcutRecorderDidCancelRecording(_ recorder: ShortcutRecorderField) {
        customShortcutField.textColor = .labelColor
        updateHotkeyUI()
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
