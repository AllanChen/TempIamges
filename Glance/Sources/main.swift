import AppKit
import os.log

let osLog = OSLog(subsystem: "com.imagehoverpreview", category: "Startup")
os_log("Application starting up", log: osLog, type: .info)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()