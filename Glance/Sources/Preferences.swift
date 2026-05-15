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

    var theme: Theme {
        get {
            let raw = defaults.string(forKey: "\(suiteName).theme") ?? ""
            return Theme(rawValue: raw) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: "\(suiteName).theme") }
    }

    var maxPreviewSize: CGFloat {
        get { CGFloat(defaults.double(forKey: "\(suiteName).maxSize")) }
        set { defaults.set(Double(newValue), forKey: "\(suiteName).maxSize") }
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

    var hotkeyModifiers: NSEvent.ModifierFlags {
        get {
            let rawValue = UInt(defaults.integer(forKey: "\(suiteName).hotkeyModifiers"))
            return NSEvent.ModifierFlags(rawValue: rawValue)
        }
        set { defaults.set(Int(newValue.rawValue), forKey: "\(suiteName).hotkeyModifiers") }
    }

    var hotkeyRequiresOption: Bool {
        get { defaults.bool(forKey: "\(suiteName).hotkeyRequiresOption") }
        set { defaults.set(newValue, forKey: "\(suiteName).hotkeyRequiresOption") }
    }

    var hotkeyRequiresControl: Bool {
        get { defaults.bool(forKey: "\(suiteName).hotkeyRequiresControl") }
        set { defaults.set(newValue, forKey: "\(suiteName).hotkeyRequiresControl") }
    }

    private init() {
        registerDefaults()
    }

    private func registerDefaults() {
        let defaultValues: [String: Any] = [
            "\(suiteName).maxSize": 400.0,
            "\(suiteName).enabled": true,
            "\(suiteName).launchAtLogin": false,
            "\(suiteName).readClipboard": true,
            "\(suiteName).hotkeyModifiers": Int(NSEvent.ModifierFlags([.control]).rawValue),
            "\(suiteName).hotkeyRequiresOption": false,
            "\(suiteName).hotkeyRequiresControl": true
        ]
        defaults.register(defaults: defaultValues)
    }

    func resetToDefaults() {
        maxPreviewSize = 400
        enabled = true
        launchAtLogin = false
        readClipboard = true
        loginURL = nil
        hotkeyModifiers = [.control]
        hotkeyRequiresOption = false
        hotkeyRequiresControl = true
    }
}
