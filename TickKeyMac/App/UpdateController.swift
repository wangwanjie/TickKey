import AppKit
#if SPARKLE_ENABLED
import Sparkle
#endif

@MainActor
final class UpdateController: NSObject {
    static let shared = UpdateController()
    #if SPARKLE_ENABLED
    private var controller: SPUStandardUpdaterController?
    #endif
    var configured: Bool {
        #if SPARKLE_ENABLED
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return false }
        return true
        #else
        return false
        #endif
    }
    func start() {
        #if SPARKLE_ENABLED
        if configured {
            controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            #if !DEBUG
            do { try controller?.updater.start() } catch { MacAlerts.error(error) }
            #endif
        }
        #endif
    }
    @objc func check() {
        #if SPARKLE_ENABLED
        if let controller {
            #if DEBUG
            do { try controller.updater.start() } catch { MacAlerts.error(error); return }
            #endif
            controller.checkForUpdates(nil); return
        }
        #endif
        MacAlerts.message(L.text("updates.unconfigured"))
    }
}

@MainActor
enum MacAlerts {
    static func message(_ message: String) { let alert = NSAlert(); alert.messageText = "TickKey"; alert.informativeText = message; alert.addButton(withTitle: L.text("close")); alert.runModal() }
    static func error(_ error: Error) { message(error.localizedDescription) }
    static func confirm(_ message: String) -> Bool {
        let alert = NSAlert(); alert.messageText = "TickKey"; alert.informativeText = message
        alert.addButton(withTitle: L.text("continue")); alert.addButton(withTitle: L.text("cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
