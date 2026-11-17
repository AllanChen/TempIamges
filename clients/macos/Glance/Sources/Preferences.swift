import AppKit

class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let suiteName = "com.glance"

    enum Theme: String, CaseIterable {
        case system, light, dark
        /// nil = follow the OS. Otherwise pin to aqua / darkAqua.
        var appearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light:  return NSAppearance(named: .aqua)
            case .dark:   return NSAppearance(named: .darkAqua)
            }
        }
        var displayName: String {
            switch self {
            case .system: return "System".localized
            case .light:  return "Light".localized
            case .dark:   return "Dark".localized
            }
        }
    }

    enum AppLanguage: String, CaseIterable {
        case english = "en"
        case chinese = "zh-Hans"
        case japanese = "ja"
        case german = "de"

        /// The language that follows the system language (English when the system language is not supported).
        static var systemDefault: AppLanguage {
            AppLanguage(rawValue: SystemLanguage.code(for: SystemLanguage.systemIdentifiers())) ?? .english
        }

        var displayName: String {
            switch self {
            case .english: return "English"
            case .chinese: return "简体中文"
            case .japanese: return "日本語"
            case .german: return "Deutsch"
            }
        }
    }

    enum ActivationMode: String, CaseIterable {
        /// Default. ⌥Space collides with the ChatGPT desktop app's shortcut.
        case optionK = "optionK"
        case optionSpace = "optionSpace"
        case option = "option"
        case custom = "custom"

        var displayName: String {
            switch self {
            case .optionK: return "⌥ K"
            case .optionSpace: return "⌥ Space".localized
            case .option: return "Option (⌥)".localized
            case .custom: return "Custom".localized
            }
        }
    }

    var theme: Theme {
        get {
            let raw = defaults.string(forKey: "\(suiteName).theme") ?? ""
            return Theme(rawValue: raw) ?? .dark
        }
        set { defaults.set(newValue.rawValue, forKey: "\(suiteName).theme") }
    }

    /// The user's language. Until one is chosen (the first launch) it follows the system language, falling back to
    /// English when that is not supported, and that first value is kept. Choosing a language later replaces it.
    var appLanguage: AppLanguage {
        get {
            let key = "\(suiteName).language"
            if let raw = defaults.string(forKey: key), let language = AppLanguage(rawValue: raw) { return language }
            let detected = AppLanguage.systemDefault
            defaults.set(detected.rawValue, forKey: key)
            return detected
        }
        set {
            defaults.set(newValue.rawValue, forKey: "\(suiteName).language")
            UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }

    /// Dismissing setup is a valid choice; explicit permission actions still reopen it.
    var permissionSetupDismissed: Bool {
        get { defaults.bool(forKey: "\(suiteName).permissionSetupDismissed") }
        set { defaults.set(newValue, forKey: "\(suiteName).permissionSetupDismissed") }
    }

    /// Peek (select text anywhere, press the hotkey, see what it points at).
    /// It needs Accessibility (including event listening), so it is opt-in. The stored
    /// key keeps its original name so existing choices carry over.
    var peekEnabled: Bool {
        get { defaults.bool(forKey: "\(suiteName).enabled") }
        set { defaults.set(newValue, forKey: "\(suiteName).enabled") }
    }

    /// True exactly once, on a fresh install: the permission guide is offered
    /// over Home. Installs that already ran an opt-in build (they carry the
    /// Peek migration marker) are upgrades and are not shown the guide.
    func consumeFirstRun() -> Bool {
        let key = "\(suiteName).firstRunGuideOffered"
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        return !defaults.bool(forKey: "\(suiteName).peekOptInMigrated")
    }

    /// Peek used to be on by default and asked for permissions at first launch.
    /// Run once: someone who never touched the setting but already had Peek
    /// working keeps it on; an explicit choice is never overridden.
    func migratePeekOptIn(alreadySetUp: Bool) {
        let migratedKey = "\(suiteName).peekOptInMigrated"
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        let storedChoice = Bundle.main.bundleIdentifier
            .flatMap { defaults.persistentDomain(forName: $0)?["\(suiteName).enabled"] }
        if storedChoice == nil, alreadySetUp { peekEnabled = true }
    }

    /// Whether the one-time "make Glance the default viewer?" offer was shown
    /// after a Finder open. Shown at most once, whatever the answer.
    var hasOfferedDefaultViewer: Bool {
        get { defaults.bool(forKey: "\(suiteName).offeredDefaultViewer") }
        set { defaults.set(newValue, forKey: "\(suiteName).offeredDefaultViewer") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "\(suiteName).launchAtLogin") }
        set { defaults.set(newValue, forKey: "\(suiteName).launchAtLogin") }
    }

    var readClipboard: Bool {
        get { defaults.bool(forKey: "\(suiteName).readClipboard") }
        set { defaults.set(newValue, forKey: "\(suiteName).readClipboard") }
    }

    var loginURL: String? {
        get { defaults.string(forKey: "\(suiteName).loginURL") }
        set { defaults.set(newValue, forKey: "\(suiteName).loginURL") }
    }

    var activationMode: ActivationMode {
        get {
            let raw = defaults.string(forKey: "\(suiteName).activationMode") ?? ""
            if raw.isEmpty {
                let hadControl = defaults.bool(forKey: "\(suiteName).hotkeyRequiresControl")
                let hadOption  = defaults.bool(forKey: "\(suiteName).hotkeyRequiresOption")
                return (hadControl || hadOption) ? .option : .optionK
            }
            return ActivationMode(rawValue: raw) ?? .optionK
        }
        set { defaults.set(newValue.rawValue, forKey: "\(suiteName).activationMode") }
    }

    var customHotkeyModifiers: NSEvent.ModifierFlags {
        get {
            let rawValue = UInt(defaults.integer(forKey: "\(suiteName).customHotkeyModifiers"))
            return NSEvent.ModifierFlags(rawValue: rawValue)
        }
        set { defaults.set(Int(newValue.rawValue), forKey: "\(suiteName).customHotkeyModifiers") }
    }

    /// Key code for the non-modifier key in a combo hotkey (e.g. 'L' in ⌘L).
    /// When nil, the hotkey is modifier-only (legacy behaviour).
    var customHotkeyKeyCode: UInt16? {
        get {
            let raw = defaults.integer(forKey: "\(suiteName).customHotkeyKeyCode")
            return raw == 0 ? nil : UInt16(raw)
        }
        set { defaults.set(newValue.map(Int.init) ?? 0, forKey: "\(suiteName).customHotkeyKeyCode") }
    }

    var effectiveModifiers: NSEvent.ModifierFlags {
        switch activationMode {
        case .optionK, .optionSpace, .option: return .option
        case .custom: return customHotkeyModifiers
        }
    }

    var effectiveKeyCode: UInt16? {
        switch activationMode {
        case .optionK: return 40   // kVK_ANSI_K
        case .optionSpace: return 49
        case .option: return nil
        case .custom: return customHotkeyKeyCode
        }
    }

    /// True when the custom hotkey uses a combo (modifiers + regular key).
    var usesComboHotkey: Bool {
        effectiveKeyCode != nil
    }

    private init() {
        registerDefaults()
    }

    #if MAS
    private static let defaultActivationMode = ActivationMode.custom
    private static let defaultCustomModifiers = Int(NSEvent.ModifierFlags([.control, .option]).rawValue)
    private static let defaultCustomKeyCode = 40   // kVK_ANSI_K
    #else
    private static let defaultActivationMode = ActivationMode.optionK
    private static let defaultCustomModifiers = 0
    private static let defaultCustomKeyCode = 0
    #endif

    private func registerDefaults() {
        let defaultValues: [String: Any] = [
            "\(suiteName).enabled": false,
            "\(suiteName).launchAtLogin": false,
            "\(suiteName).readClipboard": true,
            "\(suiteName).theme": Theme.dark.rawValue,
            // The App Store build defaults to ⌃⌥K: macOS 15 refuses system
            // hotkeys that use only ⌥, which the sandbox may fall back to.
            "\(suiteName).activationMode": Self.defaultActivationMode.rawValue,
            "\(suiteName).customHotkeyModifiers": Self.defaultCustomModifiers,
            "\(suiteName).customHotkeyKeyCode": Self.defaultCustomKeyCode
        ]
        defaults.register(defaults: defaultValues)
    }

    func resetToDefaults() {
        permissionSetupDismissed = false
        peekEnabled = false
        launchAtLogin = false
        readClipboard = true
        loginURL = nil
        theme = .dark
        activationMode = .optionK
        customHotkeyModifiers = []
        customHotkeyKeyCode = nil
        appLanguage = AppLanguage.systemDefault
    }
}
