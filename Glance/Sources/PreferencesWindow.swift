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
    private var themePopup: NSPopUpButton!
    private var recordedModifiers: NSEvent.ModifierFlags = []
    private var recordedKeyCode: UInt16?

    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 480, height: 560)
        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = "Preferences".localized
        self.center()
        self.isReleasedWhenClosed = false

        // Frosted dark chrome — the blur runs full height under a transparent
        // title bar so the window reads as one continuous translucent surface.
        self.appearance = NSAppearance(named: .darkAqua)
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.isOpaque = false
        self.backgroundColor = .clear

        setupUI()
        loadSettings()
    }

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        // Frosted base — fills the whole window, blurs the wallpaper behind it.
        let frost = NSVisualEffectView(frame: contentView.bounds)
        frost.material = .hudWindow
        frost.blendingMode = .behindWindow
        frost.state = .active
        frost.appearance = NSAppearance(named: .vibrantDark)
        frost.autoresizingMask = [.width, .height]
        frost.wantsLayer = true
        contentView.addSubview(frost)

        // Black tint biases the frost toward black for the "磨砂黑" look.
        let tint = NSView(frame: contentView.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0, alpha: 0.32).cgColor
        tint.autoresizingMask = [.width, .height]
        contentView.addSubview(tint)

        // Flipped container so the layout reads top-down.
        let container = FlippedView(frame: contentView.bounds)
        container.autoresizingMask = [.width, .height]
        contentView.addSubview(container)

        // Title
        let titleLabel = NSTextField(labelWithString: "Glance Preferences".localized)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 24, y: 24, width: 432, height: 30)
        container.addSubview(titleLabel)

        // ---- Card 1: Appearance ----
        let card1 = makeCard(NSRect(x: 20, y: 72, width: 440, height: 132))
        container.addSubview(card1)
        container.addSubview(makeSectionHeader("Appearance".localized, at: NSRect(x: 36, y: 86, width: 408, height: 14)))

        container.addSubview(makeFieldLabel("Language".localized, at: NSRect(x: 36, y: 114, width: 120, height: 22)))
        languagePopup = NSPopUpButton(frame: NSRect(x: 196, y: 112, width: 244, height: 26), pullsDown: false)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        for lang in Preferences.AppLanguage.allCases {
            languagePopup.addItem(withTitle: lang.displayName)
            languagePopup.lastItem?.representedObject = lang.rawValue
        }
        container.addSubview(languagePopup)

        container.addSubview(makeFieldLabel("Theme".localized, at: NSRect(x: 36, y: 154, width: 120, height: 22)))
        themePopup = NSPopUpButton(frame: NSRect(x: 196, y: 152, width: 244, height: 26), pullsDown: false)
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        for t in Preferences.Theme.allCases {
            themePopup.addItem(withTitle: t.displayName)
            themePopup.lastItem?.representedObject = t.rawValue
        }
        container.addSubview(themePopup)

        // ---- Card 2: General ----
        let card2 = makeCard(NSRect(x: 20, y: 220, width: 440, height: 132))
        container.addSubview(card2)
        container.addSubview(makeSectionHeader("General".localized, at: NSRect(x: 36, y: 234, width: 408, height: 14)))

        enabledCheckbox = makeCheckbox("Enable Image Hover Preview".localized, action: #selector(enabledToggled))
        enabledCheckbox.frame = NSRect(x: 36, y: 264, width: 408, height: 22)
        container.addSubview(enabledCheckbox)

        readClipboardCheckbox = makeCheckbox("Read clipboard when no text is selected".localized, action: #selector(readClipboardToggled))
        readClipboardCheckbox.frame = NSRect(x: 36, y: 294, width: 408, height: 22)
        container.addSubview(readClipboardCheckbox)

        launchAtLoginCheckbox = makeCheckbox("Launch at Login".localized, action: #selector(launchAtLoginToggled))
        launchAtLoginCheckbox.frame = NSRect(x: 36, y: 324, width: 408, height: 22)
        container.addSubview(launchAtLoginCheckbox)

        // ---- Card 3: Activation Hotkey ----
        let card3 = makeCard(NSRect(x: 20, y: 368, width: 440, height: 140))
        container.addSubview(card3)
        container.addSubview(makeSectionHeader("Activation Hotkey".localized, at: NSRect(x: 36, y: 382, width: 408, height: 14)))

        let hotkeyDesc = NSTextField(labelWithString: "Select a path, then press the shortcut to show or hide Peek:".localized)
        hotkeyDesc.font = NSFont.systemFont(ofSize: 12)
        hotkeyDesc.textColor = NSColor(white: 1, alpha: 0.55)
        hotkeyDesc.lineBreakMode = .byWordWrapping
        hotkeyDesc.maximumNumberOfLines = 2
        hotkeyDesc.frame = NSRect(x: 36, y: 404, width: 408, height: 32)
        container.addSubview(hotkeyDesc)

        modePopup = NSPopUpButton(frame: NSRect(x: 36, y: 444, width: 150, height: 26), pullsDown: false)
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        for m in Preferences.ActivationMode.allCases {
            modePopup.addItem(withTitle: m.displayName.localized)
            modePopup.lastItem?.representedObject = m.rawValue
        }
        container.addSubview(modePopup)

        customShortcutField = ShortcutRecorderField(frame: NSRect(x: 196, y: 444, width: 244, height: 26))
        customShortcutField.isEditable = false
        customShortcutField.isSelectable = false
        customShortcutField.alignment = .center
        customShortcutField.isBordered = false
        customShortcutField.drawsBackground = true
        customShortcutField.backgroundColor = NSColor(white: 1, alpha: 0.10)
        customShortcutField.textColor = .white
        customShortcutField.wantsLayer = true
        customShortcutField.layer?.cornerRadius = 6
        customShortcutField.layer?.masksToBounds = true
        customShortcutField.font = NSFont.systemFont(ofSize: 13)
        customShortcutField.placeholderString = "Click to record shortcut".localized
        customShortcutField.recorderDelegate = self
        container.addSubview(customShortcutField)

        currentHotkeyLabel = NSTextField(labelWithString: "")
        currentHotkeyLabel.font = NSFont.systemFont(ofSize: 11)
        currentHotkeyLabel.textColor = NSColor(white: 1, alpha: 0.50)
        currentHotkeyLabel.frame = NSRect(x: 36, y: 478, width: 408, height: 18)
        container.addSubview(currentHotkeyLabel)

        // ---- Footer ----
        let resetButton = NSButton(title: "Reset to Defaults".localized, target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 340, y: 520, width: 120, height: 28)
        container.addSubview(resetButton)
    }

    // MARK: - UI builders

    private func makeCard(_ frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderColor = NSColor(white: 1, alpha: 0.09).cgColor
        card.layer?.borderWidth = 1
        return card
    }

    private func makeSectionHeader(_ text: String, at frame: NSRect) -> NSTextField {
        let lbl = NSTextField(labelWithString: text.uppercased())
        lbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        lbl.textColor = NSColor(white: 1, alpha: 0.40)
        lbl.frame = frame
        return lbl
    }

    private func makeFieldLabel(_ text: String, at frame: NSRect) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        lbl.textColor = .white
        lbl.frame = frame
        return lbl
    }

    private func makeCheckbox(_ title: String, action: Selector) -> NSButton {
        let btn = NSButton(checkboxWithTitle: title, target: self, action: action)
        btn.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13)
            ]
        )
        return btn
    }

    private func loadSettings() {
        let prefs = Preferences.shared
        enabledCheckbox.state = prefs.enabled ? .on : .off
        readClipboardCheckbox.state = prefs.readClipboard ? .on : .off
        launchAtLoginCheckbox.state = prefs.launchAtLogin ? .on : .off
        updateModePopup()
        updateHotkeyUI()
        updateLanguagePopup()
        updateThemePopup()
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

    private func updateThemePopup() {
        let current = Preferences.shared.theme.rawValue
        for (index, item) in themePopup.itemArray.enumerated() {
            if (item.representedObject as? String) == current {
                themePopup.selectItem(at: index)
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

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let theme = Preferences.Theme(rawValue: raw),
              theme != Preferences.shared.theme else { return }
        Preferences.shared.theme = theme
        NSApp.appearance = theme.appearance
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    private func updateCurrentHotkeyLabel() {
        let prefs = Preferences.shared
        let symbol = hotkeyDisplayString(
            modifiers: prefs.effectiveModifiers,
            keyCode: prefs.effectiveKeyCode
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
        case 106: return "f16"
        case 107: return "f14"
        case 109: return "f10"
        case 111: return "f12"
        case 113: return "f15"
        case 114: return "help"
        case 115: return "home"
        case 116: return "pageup"
        case 117: return "⌦"
        case 118: return "f4"
        case 119: return "end"
        case 120: return "f2"
        case 121: return "pagedown"
        case 122: return "f1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
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

/// Top-left origin so the preferences layout can be expressed top-down.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
