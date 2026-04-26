import AppKit

class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let suiteName = "com.imagehoverpreview"

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

    var hotkeyModifiers: NSEvent.ModifierFlags {
        get {
            let rawValue = UInt(defaults.integer(forKey: "\(suiteName).hotkeyModifiers"))
            return NSEvent.ModifierFlags(rawValue: rawValue)
        }
        set { defaults.set(Int(newValue.rawValue), forKey: "\(suiteName).hotkeyModifiers") }
    }

    var hotkeyRequiresShift: Bool {
        get { defaults.bool(forKey: "\(suiteName).hotkeyRequiresShift") }
        set { defaults.set(newValue, forKey: "\(suiteName).hotkeyRequiresShift") }
    }

    var hotkeyRequiresCommand: Bool {
        get { defaults.bool(forKey: "\(suiteName).hotkeyRequiresCommand") }
        set { defaults.set(newValue, forKey: "\(suiteName).hotkeyRequiresCommand") }
    }

    private init() {
        registerDefaults()
    }

    private func registerDefaults() {
        let defaultValues: [String: Any] = [
            "\(suiteName).maxSize": 400.0,
            "\(suiteName).enabled": true,
            "\(suiteName).launchAtLogin": false,
            "\(suiteName).hotkeyModifiers": Int(NSEvent.ModifierFlags([.command, .shift]).rawValue),
            "\(suiteName).hotkeyRequiresShift": true,
            "\(suiteName).hotkeyRequiresCommand": true
        ]
        defaults.register(defaults: defaultValues)
    }

    func resetToDefaults() {
        maxPreviewSize = 400
        enabled = true
        launchAtLogin = false
        hotkeyModifiers = [.command, .shift]
        hotkeyRequiresShift = true
        hotkeyRequiresCommand = true
    }
}
