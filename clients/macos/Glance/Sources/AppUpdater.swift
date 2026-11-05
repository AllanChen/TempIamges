import AppKit
import Sparkle

/// Sparkle validates signed archives before installation. Never publish an
/// unsigned update or route this feed to the developer's unnotarized builds.
final class AppUpdater: NSObject {
    static let shared = AppUpdater()
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var started = false

    func start() {
        guard !started else { return }
        controller.startUpdater()
        started = true
    }

    @objc func checkForUpdates(_ sender: Any?) {
        start()
        controller.checkForUpdates(sender)
    }
}
