import AppKit
import os.log

let suiteName = "com.glance"
let langKey = "\(suiteName).language"
let storedLang = UserDefaults.standard.string(forKey: langKey)
if let lang = storedLang, !lang.isEmpty {
    UserDefaults.standard.set([lang], forKey: "AppleLanguages")
    UserDefaults.standard.synchronize()
}

let osLog = OSLog(subsystem: "com.glance", category: "Startup")
os_log("Application starting up", log: osLog, type: .info)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()