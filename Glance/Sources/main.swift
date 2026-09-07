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
// Regular activation so Glance appears in the Dock and Cmd+Tab. The menu-bar
// item still works; this only adds the Dock presence the user asked for.
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()