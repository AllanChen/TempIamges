import AppKit

protocol ShortcutRecorderDelegate: AnyObject {
    func shortcutRecorderDidBeginRecording(_ recorder: ShortcutRecorderField)
    func shortcutRecorder(_ recorder: ShortcutRecorderField, didRecordModifiers modifiers: NSEvent.ModifierFlags, keyCode: UInt16?)
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
        recorderDelegate?.shortcutRecorder(self, didRecordModifiers: mods, keyCode: nil)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 {
            cancelRecording()
            return
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        recorderDelegate?.shortcutRecorder(self, didRecordModifiers: mods, keyCode: event.keyCode)
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
    private var recordedKeyCode: UInt16?

    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 480, height: 400)
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
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 24, y: 350, width: 430, height: 28)
        containerView.addSubview(titleLabel)

        let languageLabel = NSTextField(labelWithString: "Language".localized)
        languageLabel.font = NSFont.boldSystemFont(ofSize: 14)
        languageLabel.frame = NSRect(x: 24, y: 316, width: 200, height: 22)
        containerView.addSubview(languageLabel)

        languagePopup = NSPopUpButton(frame: NSRect(x: 24, y: 290, width: 220, height: 26), pullsDown: false)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        for lang in Preferences.AppLanguage.allCases {
            languagePopup.addItem(withTitle: lang.displayName)
            languagePopup.lastItem?.representedObject = lang.rawValue
        }
        containerView.addSubview(languagePopup)

        let generalLabel = NSTextField(labelWithString: "General".localized)
        generalLabel.font = NSFont.boldSystemFont(ofSize: 14)
        generalLabel.frame = NSRect(x: 24, y: 258, width: 430, height: 22)
        containerView.addSubview(generalLabel)

        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Image Hover Preview".localized, target: self, action: #selector(enabledToggled))
        enabledCheckbox.frame = NSRect(x: 24, y: 228, width: 320, height: 22)
        containerView.addSubview(enabledCheckbox)

        readClipboardCheckbox = NSButton(checkboxWithTitle: "Read clipboard when no text is selected".localized, target: self, action: #selector(readClipboardToggled))
        readClipboardCheckbox.frame = NSRect(x: 24, y: 200, width: 420, height: 22)
        containerView.addSubview(readClipboardCheckbox)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login".localized, target: self, action: #selector(launchAtLoginToggled))
        launchAtLoginCheckbox.frame = NSRect(x: 24, y: 172, width: 320, height: 22)
        containerView.addSubview(launchAtLoginCheckbox)

        let hotkeyLabel = NSTextField(labelWithString: "Activation Hotkey".localized)
        hotkeyLabel.font = NSFont.boldSystemFont(ofSize: 14)
        hotkeyLabel.frame = NSRect(x: 24, y: 130, width: 200, height: 22)
        containerView.addSubview(hotkeyLabel)

        let hotkeyDesc = NSTextField(labelWithString: "Hold these keys while hovering to show previews:".localized)
        hotkeyDesc.font = NSFont.systemFont(ofSize: 12)
        hotkeyDesc.textColor = .secondaryLabelColor
        hotkeyDesc.frame = NSRect(x: 24, y: 108, width: 420, height: 20)
        containerView.addSubview(hotkeyDesc)

        modePopup = NSPopUpButton(frame: NSRect(x: 24, y: 78, width: 160, height: 26), pullsDown: false)
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        for m in Preferences.ActivationMode.allCases {
            modePopup.addItem(withTitle: m.displayName.localized)
            modePopup.lastItem?.representedObject = m.rawValue
        }
        containerView.addSubview(modePopup)

        customShortcutField = ShortcutRecorderField(frame: NSRect(x: 196, y: 78, width: 220, height: 26))
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
        currentHotkeyLabel.frame = NSRect(x: 24, y: 52, width: 300, height: 20)
        containerView.addSubview(currentHotkeyLabel)

        let resetButton = NSButton(title: "Reset to Defaults".localized, target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 336, y: 20, width: 120, height: 28)
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
            customShortcutField.stringValue = hotkeyDisplayString(
                modifiers: prefs.customHotkeyModifiers,
                keyCode: prefs.customHotkeyKeyCode
            )
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
        let prefs = Preferences.shared
        let symbol = hotkeyDisplayString(
            modifiers: prefs.effectiveModifiers,
            keyCode: prefs.customHotkeyKeyCode
        )
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

    private func hotkeyDisplayString(modifiers: NSEvent.ModifierFlags, keyCode: UInt16?) -> String {
        var result = modifierString(modifiers)
        if let keyCode = keyCode, let char = keyCodeToCharacter(keyCode) {
            result += (result.isEmpty ? "" : "+") + char.uppercased()
        }
        return result
    }

    private func keyCodeToCharacter(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 0:   return "a"
        case 1:   return "s"
        case 2:   return "d"
        case 3:   return "f"
        case 4:   return "h"
        case 5:   return "g"
        case 6:   return "z"
        case 7:   return "x"
        case 8:   return "c"
        case 9:   return "v"
        case 11:  return "b"
        case 12:  return "q"
        case 13:  return "w"
        case 14:  return "e"
        case 15:  return "r"
        case 16:  return "y"
        case 17:  return "t"
        case 18:  return "1"
        case 19:  return "2"
        case 20:  return "3"
        case 21:  return "4"
        case 22:  return "6"
        case 23:  return "5"
        case 24:  return "="
        case 25:  return "9"
        case 26:  return "7"
        case 27:  return "-"
        case 28:  return "8"
        case 29:  return "0"
        case 30:  return "]"
        case 31:  return "o"
        case 32:  return "u"
        case 33:  return "["
        case 34:  return "i"
        case 35:  return "p"
        case 36:  return "↩"
        case 37:  return "l"
        case 38:  return "j"
        case 39:  return "'"
        case 40:  return "k"
        case 41:  return ";"
        case 42:  return "\\"
        case 43:  return ","
        case 44:  return "/"
        case 45:  return "n"
        case 46:  return "m"
        case 47:  return "."
        case 48:  return "⇥"
        case 49:  return "␣"
        case 50:  return "`"
        case 51:  return "⌫"
        case 52:  return "⌤"
        case 53:  return "⎋"
        case 65:  return "."
        case 67:  return "*"
        case 69:  return "+"
        case 71:  return "⌧"
        case 75:  return "/"
        case 76:  return "↩"
        case 78:  return "-"
        case 81:  return "="
        case 82:  return "0"
        case 83:  return "1"
        case 84:  return "2"
        case 85:  return "3"
        case 86:  return "4"
        case 87:  return "5"
        case 88:  return "6"
        case 89:  return "7"
        case 91:  return "8"
        case 92:  return "9"
        case 96:  return "f5"
        case 97:  return "f6"
        case 98:  return "f7"
        case 99:  return "f3"
        case 100: return "f8"
        case 101: return "f9"
        case 103: return "f11"
        case 105: return "f13"
        case 106: return "f14"
        case 107: return "f10"
        case 109: return "f12"
        case 111: return "f15"
        case 113: return "home"
        case 114: return "pageup"
        case 115: return "⌦"
        case 116: return "f4"
        case 117: return "end"
        case 118: return "f2"
        case 119: return "pagedown"
        case 120: return "f1"
        case 121: return "←"
        case 122: return "→"
        case 123: return "↓"
        case 124: return "↑"
        default:  return nil
        }
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
        recordedKeyCode = nil
        customShortcutField.stringValue = ""
        customShortcutField.placeholderString = "Press shortcut...".localized
        customShortcutField.textColor = .systemBlue
    }

    func shortcutRecorderDidCancelRecording(_ recorder: ShortcutRecorderField) {
        customShortcutField.textColor = .labelColor
        updateHotkeyUI()
    }

    func shortcutRecorder(_ recorder: ShortcutRecorderField, didRecordModifiers modifiers: NSEvent.ModifierFlags, keyCode: UInt16?) {
        if modifiers.isEmpty && keyCode == nil {
            if !recordedModifiers.isEmpty || recordedKeyCode != nil {
                recorder.endRecording()
            }
            return
        }

        // Enforce maximum of 3 keys total (modifiers + regular key).
        let modifierCount = [
            modifiers.contains(.control),
            modifiers.contains(.option),
            modifiers.contains(.command),
            modifiers.contains(.shift)
        ].filter { $0 }.count
        let keyCount = (keyCode != nil ? 1 : 0)
        if modifierCount + keyCount > 3 {
            return
        }

        recordedModifiers = recordedModifiers.union(modifiers)
        if let keyCode = keyCode {
            recordedKeyCode = keyCode
            recorder.endRecording()
        }

        customShortcutField.stringValue = hotkeyDisplayString(
            modifiers: recordedModifiers,
            keyCode: recordedKeyCode
        )
    }

    func shortcutRecorderDidEndRecording(_ recorder: ShortcutRecorderField) {
        Preferences.shared.customHotkeyModifiers = recordedModifiers
        Preferences.shared.customHotkeyKeyCode = recordedKeyCode
        customShortcutField.textColor = .labelColor
        updateHotkeyUI()
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

    @objc private func resetToDefaults() {
        Preferences.shared.resetToDefaults()
        recordedModifiers = []
        recordedKeyCode = nil
        loadSettings()
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("Preferences.preferencesDidChange")
    static let languageDidChange = Notification.Name("Preferences.languageDidChange")
}
