import AppKit
#if SPARKLE_ENABLED
  import Sparkle
#endif

// MARK: - UpdateController

/// 封装 Sparkle 生命周期，更新配置和编译开关均满足时才启用更新。
@MainActor
internal final class UpdateController: NSObject {
  static let shared = UpdateController()
  #if SPARKLE_ENABLED
    private var controller: SPUStandardUpdaterController?
  #endif
  var configured: Bool {
    #if SPARKLE_ENABLED

      guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let url = URL(string: feed), url.scheme == "https",
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            Data(base64Encoded: key)?.count == 32 else {
        return false
      }

      return true
    #else

      return false
    #endif
  }

  /// 正式版本启动自动检查；Debug 版本保留手动检查以免开发时重复联网。
  func start() {
    #if SPARKLE_ENABLED

      if configured {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        #if !DEBUG

          do {
            try controller?.updater.start()
          } catch {
            MacAlerts.error(error)
          }
        #endif
      }
    #endif
  }

  @objc func check() {
    #if SPARKLE_ENABLED

      if let controller {
        #if DEBUG

          do {
            try controller.updater.start()
          } catch {
            MacAlerts.error(error)
            return
          }
        #endif
        controller.checkForUpdates(nil)
        return
      }
    #endif
    MacAlerts.message(Localization.text("updates.unconfigured"))
  }
}

// MARK: - MacAlerts

/// 统一 Mac 模态反馈和破坏性操作前的确认提示。
@MainActor
internal enum MacAlerts {
  static func message(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "TickKey"
    alert.informativeText = message
    alert.addButton(withTitle: Localization.text("close"))
    alert.runModal()
  }

  static func error(_ error: Error) {
    message(error.localizedDescription)
  }

  static func confirm(_ message: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = "TickKey"
    alert.informativeText = message
    alert.addButton(withTitle: Localization.text("continue"))
    alert.addButton(withTitle: Localization.text("cancel"))

    return alert.runModal() == .alertFirstButtonReturn
  }
}
