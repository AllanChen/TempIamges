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

/// Compact preferences using the shared panel chrome and fixed point sizes.
/// The form scrolls independently, so resizing never shrinks text or controls.
final class PreferencesWindow: NSWindow, ShortcutRecorderDelegate {
    private static let openingSize = NSSize(width: 780, height: 640)

    private let root = PreferencesFlippedView()
    private let titlebar = PreferencesTitlebar()
    private let titleLabel = PreferencesPassthroughLabel(labelWithString: "Glance Preferences".localized)
    private let subtitleLabel = PreferencesPassthroughLabel(labelWithString: "General".localized)
    private lazy var closeTraffic = TrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), target: self, action: #selector(closeTapped))
    private lazy var minimizeTraffic = TrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), target: self, action: #selector(minimizeTapped))
    private lazy var zoomTraffic = TrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), target: self, action: #selector(zoomTapped))
    private let iconToolbar = PreferencesFlippedView()
    private lazy var generalButton = PreferencesIconButton(icon: "PrefsIconSettings", tooltip: "General".localized) { }
    private lazy var appearanceButton = PreferencesIconButton(icon: "PrefsIconGrid", tooltip: "Appearance".localized) { [weak self] in self?.scrollToAppearance() }
    private lazy var privacyButton = PreferencesIconButton(icon: "PrefsIconShield", tooltip: "Privacy".localized) { (NSApp.delegate as? AppDelegate)?.checkAndRequestPermissions() }
    private lazy var infoButton = PreferencesIconButton(icon: "PrefsIconInfo", tooltip: "Information".localized) { [weak self] in self?.showAbout() }
    private let navigation = PreferencesFlippedView()
    private var tabs: [PreferencesTab] = []
    private let form = NSView()
    private let formScroll = NSScrollView()
    private let formDocument = PreferencesFlippedView()
    private let heading = NSTextField(labelWithString: "General".localized)
    private let pageDescription = NSTextField(labelWithString: "Control startup, language, previews, and the way Glance works in the background.".localized)
    private let statusbar = PreferencesFlippedView()
    private let statusLeft = NSTextField(labelWithString: "Glance Preferences".localized)
    private let statusCenter = NSTextField(labelWithString: "Changes are saved automatically".localized)
    private lazy var resetButton = PreferencesTextButton(title: "Reset to Defaults".localized) { [weak self] in self?.resetToDefaults() }

    // Rows, in board order. The custom-shortcut row only shows in Custom mode.
    private var groups: [(label: NSTextField, rows: [PreferencesRow])] = []
    private lazy var launchRow = PreferencesRow(title: "Launch Glance at login".localized, explanation: "Keep the menu bar companion ready when macOS starts.".localized, control: .toggle)
    private lazy var peekRow = PreferencesRow(title: "Enable Peek".localized, explanation: "Preview the selected text with the activation hotkey.".localized, control: .toggle)
    private lazy var hotkeyRow = PreferencesRow(title: "Activation hotkey".localized, explanation: "", control: .selection)
    private lazy var shortcutRow = PreferencesRow(title: "Custom shortcut".localized, explanation: "Click the field, then press up to three keys.".localized, control: .shortcut)
    private lazy var languageRow = PreferencesRow(title: "Interface language".localized, explanation: "Reopen windows to apply the new language.".localized, control: .selection)
    private lazy var themeRow = PreferencesRow(title: "Theme".localized, explanation: "Follow the system, or pin Glance to light or dark.".localized, control: .selection)
    private lazy var clipboardRow = PreferencesRow(title: "Read clipboard when nothing is selected".localized, explanation: "Peek shows the clipboard when no text is selected.".localized, control: .toggle)
    private var languageAppearanceLabel: NSTextField?
    private var recordedModifiers: NSEvent.ModifierFlags = []
    private var recordedKeyCode: UInt16?

    init() {
        let frame = Self.initialFrame()
        super.init(contentRect: frame,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Preferences".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = PanelStyle.inspectBackground
        minSize = NSSize(width: 720, height: 480)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        buildUI()
        loadSettings()
    }

    /// Open at an ordinary window size, centered and clamped to the cursor's screen.
    private static func initialFrame() -> NSRect {
        ScreenManager.shared.contentFrame(for: openingSize)
    }

    // MARK: Build

    private func buildUI() {
        contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectBackground)
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        root.layer?.masksToBounds = true
        root.onLayout = { [weak self] in self?.layoutContent() }

        // 01 / Titlebar: #17181D, 58 pt.
        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        configure(titleLabel, size: 15, weight: .semibold, color: PanelStyle.textPrimary, alignment: .center)
        configure(subtitleLabel, size: 11, weight: .regular, color: PanelStyle.textTertiary, alignment: .center)
        titlebar.addSubview(titleLabel)
        titlebar.addSubview(subtitleLabel)
        [closeTraffic, minimizeTraffic, zoomTraffic].forEach { titlebar.addSubview($0) }
        root.addSubview(titlebar)

        // Icon toolbar, with fixed-size buttons.
        configurePanel(iconToolbar, color: PanelStyle.inspectToolbar)
        generalButton.isActive = true
        [generalButton, appearanceButton, privacyButton, infoButton].forEach { iconToolbar.addSubview($0) }
        root.addSubview(iconToolbar)

        // General is the only settings page.
        configurePanel(navigation, color: HistoryStyle.hex(0x111217))
        let general = PreferencesTab(title: "General".localized, icon: "PrefsIconSettings", selected: true)
        navigation.addSubview(general)
        let account = PreferencesTab(title: "Account and license".localized, icon: "PrefsIconInfo", selected: false)
        account.onPress = { [weak self] in BillingCoordinator.shared.showAccount(over: self) }
        navigation.addSubview(account)
        tabs = [general, account]
        root.addSubview(navigation)

        // 04 / General Settings: #17181D. The rows scroll when they outgrow the pane.
        form.wantsLayer = true
        form.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        formScroll.drawsBackground = false
        formScroll.hasVerticalScroller = true
        PanelStyle.styleScrollers(in: formScroll)
        formScroll.autohidesScrollers = true
        formScroll.scrollerStyle = .overlay
        formScroll.borderType = .noBorder
        formScroll.documentView = formDocument
        form.addSubview(formScroll)
        configure(heading, size: 22, weight: .semibold, color: PanelStyle.textPrimary, alignment: .left)
        configure(pageDescription, size: 12, weight: .regular, color: PanelStyle.textSecondary, alignment: .left)
        pageDescription.lineBreakMode = .byWordWrapping
        pageDescription.maximumNumberOfLines = 2
        formDocument.addSubview(heading)
        formDocument.addSubview(pageDescription)
        let languageLabel = groupLabel("Language & Appearance".localized)
        languageAppearanceLabel = languageLabel
        groups = [(groupLabel("Startup".localized), [launchRow]),
                  (groupLabel("Peek".localized), [peekRow, hotkeyRow, shortcutRow]),
                  (languageLabel, [languageRow, themeRow]),
                  (groupLabel("Clipboard".localized), [clipboardRow])]
        for group in groups {
            formDocument.addSubview(group.label)
            for row in group.rows { formDocument.addSubview(row) }
        }
        launchRow.onToggle = { value in Preferences.shared.launchAtLogin = value; NotificationCenter.default.post(name: .preferencesDidChange, object: nil) }
        peekRow.onToggle = { [weak self] value in
            Preferences.shared.peekEnabled = value
            self?.updateHotkeyRow()
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
        clipboardRow.onToggle = { value in Preferences.shared.readClipboard = value; NotificationCenter.default.post(name: .preferencesDidChange, object: nil) }
        hotkeyRow.selection.options = Preferences.ActivationMode.allCases.map { $0.displayName.localized }
        hotkeyRow.selection.onSelect = { [weak self] index in self?.modeChanged(to: Preferences.ActivationMode.allCases[index]) }
        languageRow.selection.options = Preferences.AppLanguage.allCases.map(\.displayName)
        languageRow.selection.onSelect = { [weak self] index in self?.languageChanged(to: Preferences.AppLanguage.allCases[index]) }
        themeRow.selection.options = Preferences.Theme.allCases.map(\.displayName)
        themeRow.selection.onSelect = { [weak self] index in self?.themeChanged(to: Preferences.Theme.allCases[index]) }
        shortcutRow.shortcutField.recorderDelegate = self
        root.addSubview(form)

        // 06 / Statusbar: #1A1B20 with the line stroke, 37 pt.
        configurePanel(statusbar, color: HistoryStyle.hex(0x1A1B20))
        configure(statusLeft, size: 12, weight: .regular, color: PanelStyle.textSecondary, alignment: .left)
        configure(statusCenter, size: 12, weight: .regular, color: PanelStyle.textSecondary, alignment: .center)
        statusbar.addSubview(statusCenter)
        statusbar.addSubview(statusLeft)
        statusbar.addSubview(resetButton)
        root.addSubview(statusbar)
        layoutContent()
    }

    private func groupLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        configure(label, size: 11, weight: .semibold, color: PanelStyle.textSecondary, alignment: .left)
        return label
    }

    private func configurePanel(_ view: NSView, color: NSColor) {
        view.wantsLayer = true
        view.layer?.backgroundColor = PanelStyle.resolvedCG(color)
        view.layer?.borderWidth = 1
        view.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
    }

    private func configure(_ label: NSTextField, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment) {
        label.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
    }

    // MARK: Layout (fixed point sizes; the root view is flipped)

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutContent()
    }

    private func layoutContent() {
        let width = root.bounds.width, height = root.bounds.height
        guard width > 0, height > 0 else { return }
        let titlebarHeight: CGFloat = 58
        let toolbarHeight: CGFloat = 54
        let statusHeight: CGFloat = 37
        let sidebarWidth: CGFloat = 156
        let bodyTop = titlebarHeight + toolbarHeight
        let bodyHeight = max(0, height - bodyTop - statusHeight)

        titlebar.frame = NSRect(x: 0, y: 0, width: width, height: titlebarHeight)
        [closeTraffic, minimizeTraffic, zoomTraffic].enumerated().forEach { index, button in
            button.frame = NSRect(x: 20 + CGFloat(index) * 20, y: 23, width: 12, height: 12)
        }
        titleLabel.frame = NSRect(x: 100, y: 12, width: width - 200, height: 18)
        subtitleLabel.frame = NSRect(x: 100, y: 34, width: width - 200, height: 14)

        iconToolbar.frame = NSRect(x: 0, y: titlebarHeight, width: width, height: toolbarHeight)
        for (button, x) in [(generalButton, 20), (appearanceButton, 68), (privacyButton, width - 106), (infoButton, width - 58)] as [(PreferencesIconButton, CGFloat)] {
            button.frame = NSRect(x: x, y: 8, width: 38, height: 38)
        }

        navigation.frame = NSRect(x: 0, y: bodyTop, width: sidebarWidth, height: bodyHeight)
        for (index, tab) in tabs.enumerated() {
            tab.frame = NSRect(x: 12, y: 20 + CGFloat(index) * 54, width: sidebarWidth - 24, height: 44)
        }

        form.frame = NSRect(x: sidebarWidth, y: bodyTop, width: width - sidebarWidth, height: bodyHeight)
        formScroll.frame = form.bounds
        layoutForm()

        statusbar.frame = NSRect(x: 0, y: height - statusHeight, width: width, height: statusHeight)
        statusLeft.frame = NSRect(x: 20, y: 11, width: sidebarWidth - 20, height: 15)
        let resetWidth = resetButton.designWidth
        resetButton.frame = NSRect(x: width - 20 - resetWidth, y: 8, width: resetWidth, height: 21)
        statusCenter.frame = NSRect(x: sidebarWidth + 12, y: 11,
                                   width: max(0, resetButton.frame.minX - sidebarWidth - 24), height: 15)
    }

    private func layoutForm() {
        let documentWidth = max(0, formScroll.contentSize.width)
        let inset: CGFloat = 28
        let contentWidth = max(0, documentWidth - inset * 2)
        heading.frame = NSRect(x: inset, y: 24, width: contentWidth, height: 27)
        pageDescription.frame = NSRect(x: inset, y: 62, width: contentWidth, height: 32)
        var y: CGFloat = 116
        for group in groups {
            let rows = group.rows.filter { !$0.isHidden }
            group.label.frame = NSRect(x: inset, y: y, width: contentWidth, height: 15)
            y += 30
            for row in rows {
                row.frame = NSRect(x: inset, y: y, width: contentWidth, height: 73)
                y += 85
            }
            y += 12
        }
        let contentHeight = max(formScroll.contentSize.height, y + 12)
        formDocument.frame = NSRect(x: 0, y: 0, width: documentWidth, height: contentHeight)
    }

    private func scrollToAppearance() {
        guard let label = languageAppearanceLabel else { return }
        let target = max(0, label.frame.minY - 24)
        formScroll.contentView.scroll(to: NSPoint(x: 0, y: target))
        formScroll.reflectScrolledClipView(formScroll.contentView)
    }

    // MARK: Settings

    private func loadSettings() {
        let prefs = Preferences.shared
        launchRow.toggle.isOn = prefs.launchAtLogin
        peekRow.toggle.isOn = prefs.peekEnabled
        clipboardRow.toggle.isOn = prefs.readClipboard
        hotkeyRow.selection.selectedIndex = Preferences.ActivationMode.allCases.firstIndex(of: prefs.activationMode) ?? 0
        languageRow.selection.selectedIndex = Preferences.AppLanguage.allCases.firstIndex(of: prefs.appLanguage) ?? 0
        themeRow.selection.selectedIndex = Preferences.Theme.allCases.firstIndex(of: prefs.theme) ?? 0
        updateHotkeyRow()
    }

    /// The hotkey row explains the current shortcut; the custom-shortcut row
    /// appears only in Custom mode and shows what is recorded.
    private func updateHotkeyRow() {
        let prefs = Preferences.shared
        let symbol = hotkeyDisplayString(modifiers: prefs.effectiveModifiers, keyCode: prefs.effectiveKeyCode)
        hotkeyRow.explanation = !prefs.peekEnabled ? "No hotkey while Peek is disabled.".localized
            : (symbol.isEmpty ? "(no hotkey — preview disabled)".localized : String(format: "Press %@ to show or hide Peek.".localized, symbol))
        let isCustom = prefs.activationMode == .custom
        shortcutRow.isHidden = !isCustom
        if isCustom {
            shortcutRow.shortcutField.stringValue = hotkeyDisplayString(modifiers: prefs.customHotkeyModifiers, keyCode: prefs.customHotkeyKeyCode)
            shortcutRow.shortcutField.placeholderString = "Click to record shortcut".localized
        }
        layoutContent()
    }

    private func modeChanged(to mode: Preferences.ActivationMode) {
        guard mode != Preferences.shared.activationMode else { return }
        Preferences.shared.activationMode = mode
        updateHotkeyRow()
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    private func languageChanged(to lang: Preferences.AppLanguage) {
        guard lang != Preferences.shared.appLanguage else { return }
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

    private func themeChanged(to theme: Preferences.Theme) {
        guard theme != Preferences.shared.theme else { return }
        Preferences.shared.theme = theme
        NSApp.appearance = theme.appearance
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    private func resetToDefaults() {
        Preferences.shared.resetToDefaults()
        recordedModifiers = []
        recordedKeyCode = nil
        loadSettings()
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Glance".localized
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        alert.informativeText = String(format: "Version %@\n\nThe Preview for the AI era: view images and videos, fix them with AI in place, and compare the result.".localized, version)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK".localized)
        alert.runModal()
    }

    @objc private func closeTapped() { close() }
    @objc private func minimizeTapped() { miniaturize(nil) }
    @objc private func zoomTapped() { zoom(nil) }

    // MARK: ShortcutRecorderDelegate

    func shortcutRecorderDidBeginRecording(_ recorder: ShortcutRecorderField) {
        recordedModifiers = []
        recordedKeyCode = nil
        recorder.stringValue = ""
        recorder.placeholderString = "Press shortcut...".localized
        recorder.textColor = PanelStyle.warmCue
    }

    func shortcutRecorderDidCancelRecording(_ recorder: ShortcutRecorderField) {
        recorder.textColor = PanelStyle.textPrimary
        updateHotkeyRow()
    }

    func shortcutRecorder(_ recorder: ShortcutRecorderField, didRecordModifiers modifiers: NSEvent.ModifierFlags, keyCode: UInt16?) {
        if modifiers.isEmpty && keyCode == nil {
            if !recordedModifiers.isEmpty || recordedKeyCode != nil { recorder.endRecording() }
            return
        }
        // Enforce maximum of 3 keys total (modifiers + regular key).
        let modifierCount = [modifiers.contains(.control), modifiers.contains(.option),
                             modifiers.contains(.command), modifiers.contains(.shift)].filter { $0 }.count
        if modifierCount + (keyCode != nil ? 1 : 0) > 3 { return }
        recordedModifiers = recordedModifiers.union(modifiers)
        if let keyCode {
            recordedKeyCode = keyCode
            recorder.endRecording()
        }
        recorder.stringValue = hotkeyDisplayString(modifiers: recordedModifiers, keyCode: recordedKeyCode)
    }

    func shortcutRecorderDidEndRecording(_ recorder: ShortcutRecorderField) {
        Preferences.shared.customHotkeyModifiers = recordedModifiers
        Preferences.shared.customHotkeyKeyCode = recordedKeyCode
        recorder.textColor = PanelStyle.textPrimary
        updateHotkeyRow()
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    // MARK: Hotkey text (unchanged helpers)

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
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("Preferences.preferencesDidChange")
    static let languageDidChange = Notification.Name("Preferences.languageDidChange")
}

/// Top-left origin so the board layout can be expressed top-down.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class PreferencesFlippedView: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
}

/// Titlebar: drags the window; double-click zooms. Labels pass clicks through.
private final class PreferencesTitlebar: NSView {
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { event.clickCount == 2 ? window?.zoom(nil) : window?.performDrag(with: event) }
}

private final class PreferencesPassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Board icon button: 38 × 38, radius 8, raised fill, line stroke; active = accent stroke 58 % and accent icon.
private final class PreferencesIconButton: NSView {
    var isActive = false { didSet { needsDisplay = true } }
    private let icon: String
    private let onClick: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(icon: String, tooltip: String, onClick: @escaping () -> Void) {
        self.icon = icon; self.onClick = onClick
        super.init(frame: .zero)
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        (hovering ? PanelStyle.hoverTinted(PanelStyle.inspectToolbar) : PanelStyle.inspectToolbar).setFill(); path.fill()
        (isActive ? PanelStyle.accent.withAlphaComponent(0.58) : PanelStyle.inspectLine).setStroke()
        path.lineWidth = 1; path.stroke()
        HistoryStyle.drawIcon(icon, color: isActive ? PanelStyle.accent : PanelStyle.textPrimary,
                              in: CGRect(x: 10, y: 10, width: 18, height: 18))
    }
}

/// Navigation tab: 254 × 44, radius 8. Selected: #3A2C26 fill, accent 45 % stroke,
/// accent icon and 12 semibold label; unselected: secondary icon and 12 medium label.
private final class PreferencesTab: NSView {
    var onPress: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onPress?() }
    override var mouseDownCanMoveWindow: Bool { false }
    private let title: String
    private let icon: String
    private let selected: Bool
    override var isFlipped: Bool { true }

    init(title: String, icon: String, selected: Bool) {
        self.title = title; self.icon = icon; self.selected = selected
        super.init(frame: .zero)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        (selected ? HistoryStyle.hex(0x3A2C26) : HistoryStyle.hex(0x111217)).setFill(); path.fill()
        if selected {
            PanelStyle.accent.withAlphaComponent(0.45).setStroke(); path.lineWidth = 1; path.stroke()
        }
        let tint = selected ? PanelStyle.accent : PanelStyle.textSecondary
        HistoryStyle.drawIcon(icon, color: tint, in: CGRect(x: 13, y: 13, width: 18, height: 18))
        HistoryStyle.draw(title, in: CGRect(x: 43, y: 13, width: bounds.width - 50, height: 16),
                          size: 12, weight: selected ? .semibold : .medium, color: tint)
    }
}

/// Board toggle: 38 × 21 track, radius 11; on = accent track with an ink knob at
/// x 19, off = raised track with a secondary knob at x 2. Knob is 17.
private final class PreferencesToggle: NSControl {
    var isOn = false { didSet { needsLayout = true; needsDisplay = true } }
    var onChange: ((Bool) -> Void)?
    private let knob = NSView()
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        knob.wantsLayer = true
        addSubview(knob)
        setAccessibilityRole(.checkBox)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = PanelStyle.resolvedCG(isOn ? PanelStyle.accent : PanelStyle.inspectToolbar)
        knob.layer?.backgroundColor = PanelStyle.resolvedCG(isOn ? PanelStyle.accentInk : PanelStyle.textSecondary)
        knob.layer?.cornerRadius = 8.5
        knob.frame = NSRect(x: (isOn ? 19 : 2), y: 2, width: 17, height: 17)
        setAccessibilityValue(isOn ? "1" : "0")
    }
    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.knob.animator().frame = NSRect(x: (self.isOn ? 19 : 2), y: 2, width: 17, height: 17)
        }
        onChange?(isOn)
    }
}

/// Board selection: 135 × 32 raised box, radius 8, 11 medium value at (12, 9).
/// Click pops a menu with the options.
private final class PreferencesSelection: NSView {
    var options: [String] = [] { didSet { needsDisplay = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        PanelStyle.inspectToolbar.setFill(); path.fill()
        let value = options.indices.contains(selectedIndex) ? options[selectedIndex] : ""
        HistoryStyle.draw(value, in: CGRect(x: 12, y: 9, width: bounds.width - 24, height: 14),
                          size: 12, weight: .medium, color: PanelStyle.textPrimary)
    }
    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        for (index, option) in options.enumerated() {
            let item = NSMenuItem(title: option, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.state = index == selectedIndex ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: menu.items[safe: selectedIndex], at: NSPoint(x: 0, y: bounds.height), in: self)
    }
    @objc private func pick(_ item: NSMenuItem) {
        guard item.tag != selectedIndex else { return }
        selectedIndex = item.tag
        onSelect?(item.tag)
    }
}

/// Status bar text action ("Reset to Defaults"): 12 medium, secondary; accent on hover.
private final class PreferencesTextButton: NSView {
    private let title: String
    private let onClick: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var designWidth: CGFloat { HistoryStyle.width(title, size: 12, weight: .medium) + 8 }

    init(title: String, onClick: @escaping () -> Void) {
        self.title = title; self.onClick = onClick
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func draw(_ dirtyRect: NSRect) {
        HistoryStyle.draw(title, in: CGRect(x: 4, y: 3, width: bounds.width - 8, height: 15), size: 12,
                          weight: .medium, color: hovering ? PanelStyle.accent : PanelStyle.textSecondary, align: .right)
    }
}

/// A fixed-height settings row with a trailing control and a wrapping explanation.
private final class PreferencesRow: NSView {
    enum Control { case toggle, selection, shortcut }
    var explanation: String { didSet { explanationLabel.stringValue = explanation } }
    var onToggle: ((Bool) -> Void)? { didSet { toggle.onChange = onToggle } }
    let toggle = PreferencesToggle()
    let selection = PreferencesSelection()
    let shortcutField = ShortcutRecorderField()
    private let shortcutBox = NSView()
    private let control: Control
    private let titleLabel: NSTextField
    private let explanationLabel: NSTextField
    private let divider = NSView()
    override var isFlipped: Bool { true }

    init(title: String, explanation: String, control: Control) {
        self.control = control
        self.explanation = explanation
        titleLabel = NSTextField(labelWithString: title)
        explanationLabel = NSTextField(labelWithString: explanation)
        super.init(frame: .zero)
        titleLabel.textColor = PanelStyle.textPrimary
        explanationLabel.textColor = PanelStyle.textSecondary
        for label in [titleLabel, explanationLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.maximumNumberOfLines = 2
        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        addSubview(divider)
        switch control {
        case .toggle: addSubview(toggle)
        case .selection: addSubview(selection)
        case .shortcut:
            shortcutBox.wantsLayer = true
            shortcutBox.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
            shortcutField.isEditable = false
            shortcutField.isSelectable = false
            shortcutField.isBordered = false
            shortcutField.drawsBackground = false
            shortcutField.focusRingType = .none
            shortcutField.textColor = PanelStyle.textPrimary
            shortcutField.placeholderString = "Click to record shortcut".localized
            shortcutBox.addSubview(shortcutField)
            addSubview(shortcutBox)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let controlWidth: CGFloat = control == .toggle ? 38 : 135
        let controlX = max(0, bounds.width - controlWidth)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        explanationLabel.font = PanelStyle.inspectFont(ofSize: 12)
        titleLabel.frame = NSRect(x: 0, y: 5, width: max(0, controlX - 16), height: 18)
        explanationLabel.frame = NSRect(x: 0, y: 32, width: bounds.width, height: 30)
        divider.frame = NSRect(x: 0, y: 72, width: bounds.width, height: 1)
        switch control {
        case .toggle:
            toggle.frame = NSRect(x: controlX, y: 4, width: 38, height: 21)
        case .selection:
            selection.frame = NSRect(x: controlX, y: 0, width: 135, height: 32)
        case .shortcut:
            shortcutBox.frame = NSRect(x: controlX, y: 0, width: 135, height: 32)
            shortcutBox.layer?.cornerRadius = 8
            shortcutField.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
            shortcutField.frame = NSRect(x: 10, y: 8, width: 115, height: 16)
        }
    }
}
