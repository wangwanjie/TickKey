import Combine
import UIKit

/// 管理场景窗口、外观订阅和失去活动状态时的隐私遮挡。
internal final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var observation: AnyCancellable?
  private var privacyCover: UIView?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else {
      return
    }

    let window = UIWindow(windowScene: scene)
    window.rootViewController = SettingsDrawerController()
    window.tintColor = UIColor(named: "AccentColor")
    self.window = window
    observation = AppModel.shared.$preferences.sink { [weak window] value in
      window?.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: value.appearance) ?? .unspecified
    }
    window.makeKeyAndVisible()
  }

  /// 在系统生成应用切换器快照前遮挡窗口，避免验证码进入后台预览。
  func sceneWillResignActive(_ scene: UIScene) {
    guard let window else {
      return
    }

    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .systemBackground
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    let label = UILabel(frame: cover.bounds)
    label.text = "TickKey"
    label.font = .systemFont(ofSize: 30, weight: .bold)
    label.textAlignment = .center
    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.addSubview(label)
    window.addSubview(cover)
    privacyCover = cover
  }

  /// 返回前台后移除遮挡，验证码由绝对时间重新计算。
  func sceneDidBecomeActive(_ scene: UIScene) {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
