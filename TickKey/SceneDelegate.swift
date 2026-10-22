import Combine
import UIKit

/// 管理场景窗口、外观订阅、失去活动状态时的隐私遮挡和可选的解锁保护。
internal final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var observation: AnyCancellable?
  private var lockObservation: AnyCancellable?
  private var privacyCover: UIView?
  private var lockView: LockOverlayView?

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
    // 锁定状态先于首帧建立，开启解锁保护时启动画面之后不会闪现验证码。
    lockObservation = AppLock.shared.$isLocked.sink { [weak self] locked in self?.updateLock(locked) }
  }

  /// 进入后台即上锁；控制中心、通知中心或面容 ID 弹窗只会失去活动状态，不触发上锁。
  func sceneDidEnterBackground(_ scene: UIScene) {
    AppLock.shared.lock()
  }

  /// 锁定时用覆盖层盖住整个窗口，包括已经弹出的表单；解锁后移除。
  private func updateLock(_ locked: Bool) {
    guard let window else {
      return
    }

    guard locked else {
      lockView?.removeFromSuperview()
      lockView = nil
      return
    }

    if lockView == nil {
      let view = LockOverlayView(frame: window.bounds)
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.onUnlock = { [weak self] in self?.requestUnlock(automatic: false) }
      window.addSubview(view)
      lockView = view
    }
    lockView?.localize()
    bringCoversToFront()
  }

  private func requestUnlock(automatic: Bool) {
    AppLock.shared.unlock(automatic: automatic) { [weak self] error in
      self?.lockView?.show(error)
    }
  }

  /// 锁定覆盖层位于界面之上，隐私遮挡位于最上层，后弹出的页面也不会盖过它们。
  private func bringCoversToFront() {
    if let lockView {
      window?.bringSubviewToFront(lockView)
    }
    if let privacyCover {
      window?.bringSubviewToFront(privacyCover)
    }
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
    bringCoversToFront()
    // 启动或从后台返回时自动请求一次验证；取消后由用户点击解锁按钮重试。
    requestUnlock(automatic: true)
  }
}
