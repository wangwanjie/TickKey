import UIKit

/// iOS 应用入口，窗口创建与隐私遮挡交由对应 SceneDelegate 管理。
@main
internal final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    MainThreadMonitor.shared.start()
    return true
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting session: UISceneSession,
    options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    // 直接绑定场景类型，避免仅靠 Info.plist 中的类名字符串建立入口关系。
    let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
    configuration.delegateClass = SceneDelegate.self

    return configuration
  }
}
