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
            case .system: return "System"
            case .light:  return "Light"
            case .dark:   return "Dark"
            }
        }
    }

    enum AppLanguage: String, CaseIterable {
        case english = "en"
        case chinese = "zh-Hans"

        var displayName: String {
            switch self {
            case .english: return "English"
            case .chinese: return "简体中文"
            }
        }
    }

    enum ActivationMode: String, CaseIterable {
        case option = "option"
        case custom = "custom"

        var displayName: String {
            switch self {
            case .option: return "Option (⌥)".localized
            case .custom: return "Custom".localized
            }
        }
    }

    var theme: Theme {
        get {
            let raw = defaults.string(forKey: "\(suiteName).theme") ?? ""
            return Theme(rawValue: raw) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: "\(suiteName).theme") }
    }

    var appLanguage: AppLanguage {
        get {
            let raw = defaults.string(forKey: "\(suiteName).language") ?? ""
            return AppLanguage(rawValue: raw) ?? .english
        }
        set {
            defaults.set(newValue.rawValue, forKey: "\(suiteName).language")
            UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }

    var enabled: Bool {
        get { defaults.bool(forKey: "\(suiteName).enabled") }
        set { defaults.set(newValue, forKey: "\(suiteName).enabled") }
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
                return (hadControl || hadOption) ? .option : .option
            }
            return ActivationMode(rawValue: raw) ?? .option
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

    var effectiveModifiers: NSEvent.ModifierFlags {
        switch activationMode {
        case .option: return .option
        case .custom: return customHotkeyModifiers
        }
    }

    private init() {
        registerDefaults()
    }

    private func registerDefaults() {
        let defaultValues: [String: Any] = [
            "\(suiteName).enabled": true,
            "\(suiteName).launchAtLogin": false,
            "\(suiteName).readClipboard": true,
            "\(suiteName).activationMode": ActivationMode.option.rawValue,
            "\(suiteName).customHotkeyModifiers": 0
        ]
        defaults.register(defaults: defaultValues)
    }

    func resetToDefaults() {
        enabled = true
        launchAtLogin = false
        readClipboard = true
        loginURL = nil
        activationMode = .option
        customHotkeyModifiers = []
        appLanguage = .english
    }
}
