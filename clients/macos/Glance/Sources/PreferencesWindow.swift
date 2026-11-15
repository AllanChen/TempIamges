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

/// Preferences laid out from Figma `05 · Preferences` and its Peek / Appearance
/// pages (Glance · Shizuka): a 212 pt sidebar of pages and actions, and a
/// scrolling page of settings. The root view is flipped, so frames below use
/// the Figma top-origin coordinates directly.
final class PreferencesWindow: NSWindow, ShortcutRecorderDelegate {
    private static let openingSize = NSSize(width: 960, height: 720)

    private enum Page {
        case general, peek, appearance

        var title: String {
            switch self {
            case .general: return "General".localized
            case .peek: return "Peek".localized
            case .appearance: return "Appearance".localized
            }
        }

        var summary: String {
            switch self {
            case .general: return "Control startup, language, previews, and the way Glance works in the background.".localized
            case .peek: return "Preview the selected text with the activation hotkey.".localized
            case .appearance: return "Follow the system, or pin Glance to light or dark.".localized
            }
        }
    }

    /// Figma geometry, in points from the window's top-left corner.
    private enum Metrics {
        static let titlebarHeight: CGFloat = 44
        static let sidebarWidth: CGFloat = 212
        static let navOrigin = NSPoint(x: 12, y: 60)
        static let navItemSize = NSSize(width: 188, height: 30)
        static let navItemStep: CGFloat = 32
        static let contentX: CGFloat = 276
        static let contentTop: CGFloat = 84
        static let contentTrailing: CGFloat = 64
        static let footerBottom: CGFloat = 39
        static let scrollBottom: CGFloat = 56
        static let rowHeight: CGFloat = 64
    }

    private let root = PreferencesFlippedView()
    private let titlebar = PreferencesTitlebar()
    private let titleLabel = PreferencesTextLabel("Preferences".localized, font: PanelStyle.inspectFont(ofSize: 13, weight: .medium),
                                                  color: PanelStyle.textSecondary, alignment: .center)
    private lazy var closeTraffic = TrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1), target: self, action: #selector(closeTapped))
    private lazy var minimizeTraffic = TrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1), target: self, action: #selector(minimizeTapped))
    private lazy var zoomTraffic = TrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1), target: self, action: #selector(zoomTapped))
    private let sidebarDivider = NSView()
    private var navItems: [(item: PreferencesNavItem, page: Page?)] = []
    private let formScroll = NSScrollView()
    private let formDocument = PreferencesFlippedView()
    private let heading = PreferencesTextLabel("", font: PanelStyle.titleFont(ofSize: 28), color: PanelStyle.textPrimary)
    private let pageDescription = PreferencesTextLabel("", font: PanelStyle.inspectFont(ofSize: 13), color: PanelStyle.textSecondary)
    private let footer = PreferencesTextLabel("Changes are saved automatically".localized, font: PanelStyle.inspectFont(ofSize: 12),
                                              color: PanelStyle.textTertiary)
    private lazy var resetButton = PreferencesTextButton(title: "Reset to Defaults".localized) { [weak self] in self?.resetToDefaults() }
    private var page: Page = .general

    // Groups per page, in Figma order. The custom-shortcut row only shows in Custom mode.
    private var groups: [(page: Page, label: PreferencesTextLabel, rows: [PreferencesRow])] = []
    private let themePicker = PreferencesThemePicker()
    private lazy var launchRow = PreferencesRow(title: "Launch Glance at login".localized, explanation: "Keep the menu bar companion ready when macOS starts.".localized, control: .toggle)
    private lazy var peekRow = PreferencesRow(title: "Enable Peek".localized, explanation: "Show Peek when you press the activation hotkey.".localized, control: .toggle)
    private lazy var hotkeyRow = PreferencesRow(title: "Activation hotkey".localized, explanation: "", control: .segments)
    private lazy var shortcutRow = PreferencesRow(title: "Custom shortcut".localized, explanation: "Click the field, then press up to three keys.".localized, control: .shortcut)
    private lazy var clipboardRow = PreferencesRow(title: "Read clipboard when nothing is selected".localized, explanation: "Peek shows the clipboard when no text is selected.".localized, control: .toggle)
    private lazy var languageRow = PreferencesRow(title: "Interface language".localized, explanation: "Reopen windows to apply the new language.".localized, control: .selection)
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
        appearance = PanelStyle.windowAppearance
        backgroundColor = PanelStyle.inspectChrome
        minSize = NSSize(width: 860, height: 560)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        buildUI()
        loadSettings()
        select(.general)
    }

    /// Open at the Figma window size, centered and clamped to the cursor's screen.
    private static func initialFrame() -> NSRect {
        ScreenManager.shared.contentFrame(for: openingSize)
    }

    // MARK: Build

    private func buildUI() {
        contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        root.layer?.cornerRadius = PanelStyle.Radius.window
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        root.layer?.masksToBounds = true
        root.onLayout = { [weak self] in self?.layoutContent() }

        // Titlebar: 44 pt drag region with the traffic lights and a centred 13 medium title.
        titlebar.addSubview(titleLabel)
        [closeTraffic, minimizeTraffic, zoomTraffic].forEach { titlebar.addSubview($0) }
        root.addSubview(titlebar)

        sidebarDivider.wantsLayer = true
        sidebarDivider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line))
        root.addSubview(sidebarDivider)

        // Sidebar: settings pages, then the actions that open other windows.
        let entries: [(String, PreferencesGlyph, Page?, (() -> Void)?)] = [
            ("General".localized, .adjust, .general, nil),
            ("Peek".localized, .image, .peek, nil),
            ("Appearance".localized, .sparkle, .appearance, nil),
            ("Account".localized, .user, nil, { [weak self] in BillingCoordinator.shared.showAccount(over: self) }),
            ("Privacy".localized, .shield, nil, { (NSApp.delegate as? AppDelegate)?.checkAndRequestPermissions() }),
            ("About Glance".localized, .info, nil, { [weak self] in self?.showAbout() })
        ]
        for (title, glyph, page, action) in entries {
            let item = PreferencesNavItem(title: title, glyph: glyph)
            item.onPress = { [weak self] in
                if let page { self?.select(page) } else { action?() }
            }
            navItems.append((item, page))
            root.addSubview(item)
        }

        // Page content scrolls when it outgrows the window.
        formScroll.drawsBackground = false
        formScroll.hasVerticalScroller = true
        PanelStyle.styleScrollers(in: formScroll)
        formScroll.borderType = .noBorder
        formScroll.documentView = formDocument
        root.addSubview(formScroll)
        formDocument.addSubview(heading)
        formDocument.addSubview(pageDescription)
        formDocument.addSubview(themePicker)
        groups = [(.general, groupLabel("Startup".localized), [launchRow]),
                  (.peek, groupLabel("Peek".localized), [peekRow, hotkeyRow, shortcutRow]),
                  (.peek, groupLabel("Clipboard".localized), [clipboardRow]),
                  (.appearance, groupLabel("Language".localized), [languageRow])]
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
        hotkeyRow.segments.options = Preferences.ActivationMode.allCases.map { $0.displayName.localized }
        hotkeyRow.segments.onSelect = { [weak self] index in self?.modeChanged(to: Preferences.ActivationMode.allCases[index]) }
        languageRow.selection.options = Preferences.AppLanguage.allCases.map(\.displayName)
        languageRow.selection.onSelect = { [weak self] index in self?.languageChanged(to: Preferences.AppLanguage.allCases[index]) }
        themePicker.onSelect = { [weak self] theme in self?.themeChanged(to: theme) }
        shortcutRow.shortcutField.recorderDelegate = self

        // Footer: the autosave note, with the global reset trailing it.
        root.addSubview(footer)
        root.addSubview(resetButton)
        layoutContent()
    }

    private func groupLabel(_ title: String) -> PreferencesTextLabel {
        PreferencesTextLabel(title, font: PanelStyle.inspectFont(ofSize: 12), color: PanelStyle.textTertiary)
    }

    private func select(_ page: Page) {
        self.page = page
        for entry in navItems { entry.item.isSelected = entry.page == page }
        heading.text = page.title
        pageDescription.text = page.summary
        layoutContent()
        formScroll.contentView.scroll(to: .zero)
        formScroll.reflectScrolledClipView(formScroll.contentView)
    }

    // MARK: Layout (Figma top-origin points; the root view is flipped)

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutContent()
    }

    private func layoutContent() {
        let width = root.bounds.width, height = root.bounds.height
        guard width > 0, height > 0 else { return }

        titlebar.frame = NSRect(x: 0, y: 0, width: width, height: Metrics.titlebarHeight)
        [closeTraffic, minimizeTraffic, zoomTraffic].enumerated().forEach { index, button in
            button.frame = NSRect(x: 20 + CGFloat(index) * 20, y: 16, width: 12, height: 12)
        }
        titleLabel.frame = NSRect(x: 100, y: 14, width: max(0, width - 200), height: 16)

        sidebarDivider.frame = NSRect(x: Metrics.sidebarWidth, y: Metrics.titlebarHeight,
                                      width: 1, height: max(0, height - Metrics.titlebarHeight))
        for (index, entry) in navItems.enumerated() {
            entry.item.frame = NSRect(origin: NSPoint(x: Metrics.navOrigin.x, y: Metrics.navOrigin.y + CGFloat(index) * Metrics.navItemStep),
                                      size: Metrics.navItemSize)
        }

        let scrollX = Metrics.sidebarWidth + 1
        formScroll.frame = NSRect(x: scrollX, y: Metrics.titlebarHeight, width: max(0, width - scrollX),
                                  height: max(0, height - Metrics.titlebarHeight - Metrics.scrollBottom))
        layoutForm()

        let contentWidth = max(0, width - Metrics.contentX - Metrics.contentTrailing)
        let resetWidth = resetButton.designWidth
        let footerY = height - Metrics.footerBottom
        resetButton.frame = NSRect(x: Metrics.contentX + contentWidth - resetWidth, y: footerY, width: resetWidth, height: 15)
        footer.frame = NSRect(x: Metrics.contentX, y: footerY, width: max(0, resetButton.frame.minX - Metrics.contentX - 16), height: 15)
    }

    /// Content column: Mincho title 36, 8 gap, summary 16, 36 gap, then groups
    /// of a 15 pt label, 6 gap and 64 pt rows, 32 apart.
    private func layoutForm() {
        let documentWidth = max(0, formScroll.contentSize.width)
        let x = Metrics.contentX - formScroll.frame.minX
        let contentWidth = max(0, documentWidth - x - Metrics.contentTrailing)
        var y = Metrics.contentTop - Metrics.titlebarHeight
        heading.frame = NSRect(x: x, y: y, width: contentWidth, height: 36)
        pageDescription.frame = NSRect(x: x, y: y + 44, width: contentWidth, height: 16)
        y += 96

        themePicker.isHidden = page != .appearance
        if page == .appearance {
            themePicker.frame = NSRect(x: x, y: y, width: contentWidth, height: 138)
            y += 138 + 32
        }
        let showsShortcut = Preferences.shared.activationMode == .custom
        for group in groups {
            let visible = group.page == page
            group.label.isHidden = !visible
            for row in group.rows { row.isHidden = !visible || (row === shortcutRow && !showsShortcut) }
            guard visible else { continue }
            group.label.frame = NSRect(x: x, y: y, width: contentWidth, height: 15)
            y += 15 + 6
            for row in group.rows where !row.isHidden {
                row.frame = NSRect(x: x, y: y, width: contentWidth, height: Metrics.rowHeight)
                y += Metrics.rowHeight
            }
            y += 32
        }
        let contentHeight = max(formScroll.contentSize.height, y)
        formDocument.frame = NSRect(x: 0, y: 0, width: documentWidth, height: contentHeight)
    }

    // MARK: Settings

    private func loadSettings() {
        let prefs = Preferences.shared
        launchRow.toggle.isOn = prefs.launchAtLogin
        peekRow.toggle.isOn = prefs.peekEnabled
        clipboardRow.toggle.isOn = prefs.readClipboard
        hotkeyRow.segments.selectedIndex = Preferences.ActivationMode.allCases.firstIndex(of: prefs.activationMode) ?? 0
        languageRow.selection.selectedIndex = Preferences.AppLanguage.allCases.firstIndex(of: prefs.appLanguage) ?? 0
        themePicker.selected = prefs.theme
        updateHotkeyRow()
    }

    /// The hotkey row explains the current shortcut; the custom-shortcut row
    /// appears only in Custom mode and shows what is recorded.
    private func updateHotkeyRow() {
        let prefs = Preferences.shared
        let symbol = hotkeyDisplayString(modifiers: prefs.effectiveModifiers, keyCode: prefs.effectiveKeyCode)
        hotkeyRow.explanation = !prefs.peekEnabled ? "No hotkey while Peek is disabled.".localized
            : (symbol.isEmpty ? "(no hotkey — preview disabled)".localized : String(format: "Press %@ to show or hide Peek.".localized, symbol))
        if prefs.activationMode == .custom {
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
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        // Colours are resolved once per launch, so a new theme applies after a relaunch.
        let alert = NSAlert()
        alert.messageText = "Relaunch Glance to apply the theme".localized
        alert.informativeText = "Glance needs to relaunch to switch themes. If a Widget task is still uploading, choose Later and relaunch after it finishes.".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Relaunch Now".localized)
        alert.addButton(withTitle: "Later".localized)
        if alert.runModal() == .alertFirstButtonReturn {
            AppDelegate.relaunch()
        }
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

/// One line of text drawn inside its Figma frame: vertically centred on the
/// font's ascender/descender and truncated at the tail, so neither intrinsic
/// size nor cell padding moves it. Clicks pass through.
private final class PreferencesTextLabel: NSView {
    var text: String { didSet { needsDisplay = true; setAccessibilityValue(text) } }
    var font: NSFont { didSet { needsDisplay = true } }
    var color: NSColor { didSet { needsDisplay = true } }
    private let alignment: NSTextAlignment
    override var isFlipped: Bool { true }

    init(_ text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        self.text = text; self.font = font; self.color = color; self.alignment = alignment
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityValue(text)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        PreferencesDrawing.text(text, in: bounds, font: font, color: color, alignment: alignment)
    }
}

private enum PreferencesDrawing {
    static func attributes(font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    static func width(_ text: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    /// Draws one line centred vertically in `rect` (flipped context).
    static func text(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        let lineHeight = ceil(font.ascender - font.descender)
        let line = NSRect(x: rect.minX, y: rect.minY + (rect.height - lineHeight) / 2, width: rect.width, height: lineHeight)
        NSAttributedString(string: text, attributes: attributes(font: font, color: color, alignment: alignment))
            .draw(with: line, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// Figma 16 pt stroke icons (1.5 pt, round caps), drawn in a flipped view.
private enum PreferencesGlyph {
    case adjust, image, sparkle, user, shield, info, check, chevronDown

    func draw(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        let p = { (x: CGFloat, y: CGFloat) in NSPoint(x: x, y: y) }
        switch self {
        case .adjust:
            for (a, b) in [(p(14, 2.667), p(9.333, 2.667)), (p(9.333, 1.333), p(9.333, 4)), (p(6.667, 2.667), p(2, 2.667)),
                           (p(14, 8), p(8, 8)), (p(5.333, 8), p(2, 8)), (p(5.333, 6.667), p(5.333, 9.333)),
                           (p(14, 13.333), p(10.667, 13.333)), (p(10.667, 12), p(10.667, 14.667)), (p(8, 13.333), p(2, 13.333))] {
                path.move(to: a); path.line(to: b)
            }
        case .image:
            path.appendRoundedRect(NSRect(x: 2, y: 2, width: 12, height: 12), xRadius: 1.333, yRadius: 1.333)
            path.appendOval(in: NSRect(x: 4.667, y: 4.667, width: 2.667, height: 2.667))
            path.move(to: p(14, 10)); path.line(to: p(11.943, 7.943))
            path.curve(to: p(10.057, 7.943), controlPoint1: p(11.422, 7.422), controlPoint2: p(10.578, 7.422))
            path.line(to: p(4, 14))
        case .sparkle:
            path.move(to: p(8, 2))
            for point in [p(9.267, 5.867), p(13.333, 7.133), p(9.467, 8.4), p(8, 12.267), p(6.733, 8.4), p(2.867, 7.133), p(6.733, 5.867)] {
                path.line(to: point)
            }
            path.close()
        case .user:
            path.appendOval(in: NSRect(x: 4.667, y: 2, width: 6.667, height: 6.667))
            path.move(to: p(13.333, 14))
            path.appendArc(withCenter: p(8, 14), radius: 5.333, startAngle: 0, endAngle: 180, clockwise: true)
        case .shield:
            path.move(to: p(13.333, 8.667))
            path.curve(to: p(8, 14.667), controlPoint1: p(13.333, 12), controlPoint2: p(11, 13.667))
            path.curve(to: p(2.667, 8.667), controlPoint1: p(5, 13.667), controlPoint2: p(2.667, 12))
            path.line(to: p(2.667, 4))
            path.curve(to: p(3.333, 3.333), controlPoint1: p(2.667, 3.632), controlPoint2: p(2.965, 3.333))
            path.curve(to: p(8, 1.333), controlPoint1: p(4.667, 3.333), controlPoint2: p(6.333, 2.533))
            path.curve(to: p(12.667, 3.333), controlPoint1: p(9.673, 2.54), controlPoint2: p(11.333, 3.333))
            path.curve(to: p(13.333, 4), controlPoint1: p(13.035, 3.333), controlPoint2: p(13.333, 3.632))
            path.close()
        case .info:
            path.appendOval(in: NSRect(x: 1.333, y: 1.333, width: 13.333, height: 13.333))
            path.move(to: p(8, 10.667)); path.line(to: p(8, 8))
            path.move(to: p(8, 5.333)); path.line(to: p(8.007, 5.333))
        case .check:
            path.move(to: p(13.333, 4)); path.line(to: p(6, 11.333)); path.line(to: p(2.667, 8))
        case .chevronDown:
            path.move(to: p(4, 6)); path.line(to: p(8, 10)); path.line(to: p(12, 6))
        }
        var transform = AffineTransform(translationByX: rect.minX, byY: rect.minY)
        transform.scale(rect.width / 16)
        path.transform(using: transform)
        path.lineWidth = 1.5 * rect.width / 16
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
}

/// Sidebar item: 188 × 30, radius 6, icon at (10, 7) and 13 regular label at
/// (36, 7). Selected = ink/3 fill with text/1 icon and label; otherwise a
/// text/3 icon and text/2 label.
private final class PreferencesNavItem: NSView {
    var onPress: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true; setAccessibilitySelected(isSelected) } }
    private let title: String
    private let glyph: PreferencesGlyph
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(title: String, glyph: PreferencesGlyph) {
        self.title = title; self.glyph = glyph
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func mouseDown(with event: NSEvent) { onPress?() }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            PanelStyle.inspectToolbar.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: PanelStyle.Radius.control, yRadius: PanelStyle.Radius.control).fill()
        }
        glyph.draw(in: NSRect(x: 10, y: 7, width: 16, height: 16), color: isSelected ? PanelStyle.textPrimary : PanelStyle.textTertiary)
        PreferencesDrawing.text(title, in: NSRect(x: 36, y: 7, width: max(0, bounds.width - 46), height: 16),
                                font: PanelStyle.inspectFont(ofSize: 13), color: isSelected ? PanelStyle.textPrimary : PanelStyle.textSecondary)
    }
}

/// Toggle: 30 × 18 pill with a 14 pt knob. On = text/1 track with an ink/1
/// knob at x 14; off = ink/4 track with a text/3 knob at x 2.
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
    private var knobFrame: NSRect { NSRect(x: isOn ? 14 : 2, y: 2, width: 14, height: 14) }
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = PanelStyle.resolvedCG(isOn ? PanelStyle.textPrimary : PanelStyle.surfaceElevated)
        knob.layer?.backgroundColor = PanelStyle.resolvedCG(isOn ? PanelStyle.surface : PanelStyle.textTertiary)
        knob.layer?.cornerRadius = 7
        knob.frame = knobFrame
        setAccessibilityValue(isOn ? "1" : "0")
    }
    override func mouseDown(with event: NSEvent) { flip() }
    override func accessibilityPerformPress() -> Bool { flip(); return true }
    private func flip() {
        isOn.toggle()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.knob.animator().frame = self.knobFrame
        }
        onChange?(isOn)
    }
}

/// Select: 13 regular text/2 value, 6 gap, 16 pt text/3 chevron, right-aligned
/// in its row. Click pops a menu with the options.
private final class PreferencesSelection: NSView {
    var options: [String] = [] { didSet { needsDisplay = true; updateAccessibility() } }
    var selectedIndex = 0 { didSet { needsDisplay = true; updateAccessibility(); superview?.needsLayout = true } }
    var onSelect: ((Int) -> Void)?
    private static let font = PanelStyle.inspectFont(ofSize: 13)
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    private var value: String { options.indices.contains(selectedIndex) ? options[selectedIndex] : "" }
    var designWidth: CGFloat { PreferencesDrawing.width(value, font: Self.font) + 6 + 16 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func updateAccessibility() { setAccessibilityValue(value) }

    override func draw(_ dirtyRect: NSRect) {
        let y = (bounds.height - 16) / 2
        PreferencesDrawing.text(value, in: NSRect(x: 0, y: y, width: max(0, bounds.width - 22), height: 16),
                                font: Self.font, color: PanelStyle.textSecondary, alignment: .right)
        PreferencesGlyph.chevronDown.draw(in: NSRect(x: bounds.width - 16, y: y, width: 16, height: 16), color: PanelStyle.textTertiary)
    }
    override func mouseDown(with event: NSEvent) { showMenu() }
    override func accessibilityPerformPress() -> Bool { showMenu(); return true }
    private func showMenu() {
        let menu = NSMenu()
        menu.appearance = PanelStyle.windowAppearance
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

/// Segmented preset: ink/2 track, radius 7, 2 pt padding and gap; 23 pt
/// segments with 10 pt side padding and 12 regular labels. Selected = ink/4
/// fill, radius 5, text/1 label; others text/3.
private final class PreferencesSegments: NSView {
    var options: [String] = [] { didSet { rebuild() } }
    var selectedIndex = 0 { didSet { segments.enumerated().forEach { $0.element.isSelected = $0.offset == selectedIndex } } }
    var onSelect: ((Int) -> Void)?
    private var segments: [PreferencesSegment] = []
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var designWidth: CGFloat { segments.reduce(2) { $0 + $1.designWidth + 2 } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func rebuild() {
        segments.forEach { $0.removeFromSuperview() }
        segments = options.enumerated().map { index, title in
            let segment = PreferencesSegment(title: title)
            segment.isSelected = index == selectedIndex
            segment.onPress = { [weak self] in
                guard let self, index != self.selectedIndex else { return }
                self.selectedIndex = index
                self.onSelect?(index)
            }
            addSubview(segment)
            return segment
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        layer?.cornerRadius = 7
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.overlay)
        var x: CGFloat = 2
        for segment in segments {
            segment.frame = NSRect(x: x, y: 2, width: segment.designWidth, height: 23)
            x += segment.designWidth + 2
        }
    }
}

private final class PreferencesSegment: NSView {
    var isSelected = false { didSet { needsDisplay = true; setAccessibilityValue(isSelected ? "1" : "0") } }
    var onPress: (() -> Void)?
    private let title: String
    private static let font = PanelStyle.inspectFont(ofSize: 12)
    var designWidth: CGFloat { PreferencesDrawing.width(title, font: Self.font) + 20 }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func mouseDown(with event: NSEvent) { onPress?() }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            PanelStyle.surfaceElevated.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        PreferencesDrawing.text(title, in: NSRect(x: 10, y: 4, width: max(0, bounds.width - 20), height: 15), font: Self.font,
                                color: isSelected ? PanelStyle.textPrimary : PanelStyle.textTertiary, alignment: .center)
    }
}

/// Hotkey recorder box: ink/2 fill, text/3 border, radius 6, 35 pt tall, with
/// the shortcut in mono 12. A click anywhere in the box starts recording.
private final class PreferencesShortcutBox: NSView {
    let field = ShortcutRecorderField()
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        field.font = PanelStyle.monoFont(ofSize: 12)
        field.textColor = PanelStyle.textPrimary
        field.placeholderString = "Click to record shortcut".localized
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func mouseDown(with event: NSEvent) { field.beginRecording() }
    override func layout() {
        super.layout()
        layer?.cornerRadius = PanelStyle.Radius.control
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.overlay)
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.textTertiary)
        field.frame = NSRect(x: 12, y: (bounds.height - 16) / 2, width: max(0, bounds.width - 24), height: 16)
    }
}

/// Footer text action ("Reset to Defaults"): 12 regular text/2; text/1 on hover.
private final class PreferencesTextButton: NSView {
    private let title: String
    private let onClick: () -> Void
    private static let font = PanelStyle.inspectFont(ofSize: 12)
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var designWidth: CGFloat { PreferencesDrawing.width(title, font: Self.font) }

    init(title: String, onClick: @escaping () -> Void) {
        self.title = title; self.onClick = onClick
        super.init(frame: .zero)
        setAccessibilityElement(true)
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
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
    override func draw(_ dirtyRect: NSRect) {
        PreferencesDrawing.text(title, in: bounds, font: Self.font,
                                color: hovering ? PanelStyle.textPrimary : PanelStyle.textSecondary, alignment: .right)
    }
}

/// Setting row: 64 pt with a line/hair bottom border. 13 regular text/1 title
/// at y 14 and 12 regular text/3 explanation at y 34, 16 pt before the
/// trailing control, which is centred vertically.
private final class PreferencesRow: NSView {
    enum Control { case toggle, selection, segments, shortcut }
    var explanation: String { didSet { explanationLabel.text = explanation } }
    var onToggle: ((Bool) -> Void)? { didSet { toggle.onChange = onToggle } }
    let toggle = PreferencesToggle()
    let selection = PreferencesSelection()
    let segments = PreferencesSegments()
    private let shortcutBox = PreferencesShortcutBox()
    var shortcutField: ShortcutRecorderField { shortcutBox.field }
    private let control: Control
    private let titleLabel: PreferencesTextLabel
    private let explanationLabel: PreferencesTextLabel
    private let divider = NSView()
    override var isFlipped: Bool { true }

    init(title: String, explanation: String, control: Control) {
        self.control = control
        self.explanation = explanation
        titleLabel = PreferencesTextLabel(title, font: PanelStyle.inspectFont(ofSize: 13), color: PanelStyle.textPrimary)
        explanationLabel = PreferencesTextLabel(explanation, font: PanelStyle.inspectFont(ofSize: 12), color: PanelStyle.textTertiary)
        super.init(frame: .zero)
        addSubview(titleLabel)
        addSubview(explanationLabel)
        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line))
        addSubview(divider)
        switch control {
        case .toggle: addSubview(toggle); toggle.setAccessibilityLabel(title)
        case .selection: addSubview(selection); selection.setAccessibilityLabel(title)
        case .segments: addSubview(segments); segments.setAccessibilityLabel(title)
        case .shortcut: addSubview(shortcutBox); shortcutField.setAccessibilityLabel(title)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let controlFrame: NSRect
        switch control {
        case .toggle:
            controlFrame = NSRect(x: bounds.width - 30, y: 23, width: 30, height: 18)
            toggle.frame = controlFrame
        case .selection:
            let width = selection.designWidth
            controlFrame = NSRect(x: bounds.width - width, y: 16, width: width, height: 32)
            selection.frame = controlFrame
        case .segments:
            let width = segments.designWidth
            controlFrame = NSRect(x: bounds.width - width, y: 18.5, width: width, height: 27)
            segments.frame = controlFrame
        case .shortcut:
            controlFrame = NSRect(x: bounds.width - 160, y: 14.5, width: 160, height: 35)
            shortcutBox.frame = controlFrame
        }
        let textWidth = max(0, controlFrame.minX - 16)
        titleLabel.frame = NSRect(x: 0, y: 14, width: textWidth, height: 16)
        explanationLabel.frame = NSRect(x: 0, y: 34, width: textWidth, height: 15)
        divider.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }
}

/// Appearance picker: three 112 pt previews, 16 apart, with a 13 regular
/// caption 10 below. Selected = 1.5 pt text/1 border, text/1 caption and a
/// check; otherwise a line/strong border and text/2 caption.
private final class PreferencesThemePicker: NSView {
    var selected: Preferences.Theme = .system { didSet { cards.forEach { $0.isSelected = $0.theme == selected } } }
    var onSelect: ((Preferences.Theme) -> Void)?
    private var cards: [PreferencesThemeCard] = []
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Theme".localized)
        cards = Preferences.Theme.allCases.map { theme in
            let card = PreferencesThemeCard(theme: theme)
            card.onPress = { [weak self] in
                guard let self, theme != self.selected else { return }
                self.selected = theme
                self.onSelect?(theme)
            }
            addSubview(card)
            return card
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let count = CGFloat(cards.count)
        let width = max(0, (bounds.width - 16 * (count - 1)) / count)
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: CGFloat(index) * (width + 16), y: 0, width: width, height: bounds.height)
        }
    }
}

private final class PreferencesThemeCard: NSView {
    let theme: Preferences.Theme
    var isSelected = false { didSet { needsDisplay = true; setAccessibilityValue(isSelected ? "1" : "0") } }
    var onPress: (() -> Void)?
    private static let font = PanelStyle.inspectFont(ofSize: 13)
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(theme: Preferences.Theme) {
        self.theme = theme
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(theme.displayName)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func mouseDown(with event: NSEvent) { onPress?() }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }

    override func draw(_ dirtyRect: NSRect) {
        // The previews depict the two palettes themselves, so they use the
        // fixed Washi / Sumi values rather than the running theme.
        let preview = NSRect(x: 0, y: 0, width: bounds.width, height: 112)
        let shape = NSBezierPath(roundedRect: preview.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        let ink: NSColor
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        switch theme {
        case .system:
            PanelStyle.Washi.ink1.setFill(); preview.fill()
            PanelStyle.Sumi.ink1.setFill(); NSRect(x: preview.midX, y: 0, width: preview.width / 2, height: preview.height).fill()
            ink = PanelStyle.Washi.text3
        case .light:
            PanelStyle.Washi.ink1.setFill(); preview.fill()
            ink = PanelStyle.Washi.text1
        case .dark:
            PanelStyle.Sumi.ink1.setFill(); preview.fill()
            ink = PanelStyle.Sumi.text1
        }
        for (rect, alpha) in [(NSRect(x: 13, y: 13, width: 60, height: 6), 0.9), (NSRect(x: 13, y: 29, width: 110, height: 4), 0.35),
                              (NSRect(x: 13, y: 39, width: 90, height: 4), 0.35), (NSRect(x: 13, y: 63, width: 130, height: 34), 0.12)] {
            ink.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if isSelected {
            let border = NSBezierPath(roundedRect: preview.insetBy(dx: 0.75, dy: 0.75), xRadius: 8, yRadius: 8)
            border.lineWidth = 1.5
            PanelStyle.textPrimary.setStroke(); border.stroke()
        } else {
            shape.lineWidth = 1
            PanelStyle.inspectLine.setStroke(); shape.stroke()
        }

        let title = theme.displayName
        let titleWidth = min(PreferencesDrawing.width(title, font: Self.font), max(0, bounds.width - (isSelected ? 22 : 0)))
        PreferencesDrawing.text(title, in: NSRect(x: 0, y: 122, width: titleWidth, height: 16), font: Self.font,
                                color: isSelected ? PanelStyle.textPrimary : PanelStyle.textSecondary)
        if isSelected {
            PreferencesGlyph.check.draw(in: NSRect(x: titleWidth + 6, y: 122, width: 16, height: 16), color: PanelStyle.textPrimary)
        }
    }
}
