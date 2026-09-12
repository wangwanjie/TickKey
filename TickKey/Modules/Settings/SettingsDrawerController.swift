import UIKit

/// 用子控制器承载设置和主导航，抽屉与主界面始终沿同一方向移动。
internal final class SettingsDrawerController: UIViewController {
  private let accounts = AccountsViewController()
  private lazy var navigation = UINavigationController(rootViewController: accounts)
  private let settings = SettingsViewController()
  private let dismissOverlay = UIControl()
  private var isOpen = false
  private var isAnimating = false

  override var childForStatusBarStyle: UIViewController? {
    isOpen ? settings : navigation
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    view.clipsToBounds = true
    for controller in [settings, navigation] {
      addChild(controller)
      view.addSubview(controller.view)
      controller.didMove(toParent: self)
    }
    settings.view.accessibilityIdentifier = "settings-drawer"
    settings.view.isHidden = true
    // 透明覆盖层仅拦截点击以关闭抽屉，不改变主界面的颜色。
    dismissOverlay.backgroundColor = .clear
    dismissOverlay.accessibilityIdentifier = "dismiss-settings"
    dismissOverlay.addTarget(self, action: #selector(close), for: .touchUpInside)
    dismissOverlay.isHidden = true
    view.addSubview(dismissOverlay)
    accounts.onSettings = { [weak self] in self?.setOpen(true) }
    settings.onClose = { [weak self] in self?.setOpen(false) }

    let swipe = UISwipeGestureRecognizer(target: self, action: #selector(close))
    swipe.direction = .left
    view.addGestureRecognizer(swipe)
    let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(openFromEdge(_:)))
    edge.edges = .left
    navigation.view.addGestureRecognizer(edge)
  }

  /// 根据当前窗口重新计算宽度，旋转或分屏后仍保留可点击的主界面边缘。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutDrawer()
  }

  private func layoutDrawer() {
    let bounds = view.bounds
    let width = min(bounds.width * 0.86, 440)
    let offset = isOpen ? width : 0
    settings.view.frame = CGRect(x: offset - width, y: 0, width: width, height: bounds.height)
    navigation.view.frame = bounds.offsetBy(dx: offset, dy: 0)
    dismissOverlay.frame = navigation.view.frame
  }

  /// 关闭时恢复主界面位置和辅助功能焦点，开启期间阻止操作被移开的账户。
  private func setOpen(_ open: Bool) {
    guard open != isOpen, !isAnimating else {
      return
    }
    view.endEditing(true)
    isOpen = open
    isAnimating = true
    settings.view.isHidden = false
    dismissOverlay.isHidden = false
    dismissOverlay.accessibilityLabel = Localization.text("close")
    navigation.view.accessibilityElementsHidden = open
    settings.view.accessibilityElementsHidden = !open
    setNeedsStatusBarAppearanceUpdate()
    UIView.animate(
      withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.3,
      delay: 0,
      options: [.curveEaseInOut, .beginFromCurrentState],
      animations: { self.layoutDrawer() },
      completion: { _ in
        self.isAnimating = false
        self.settings.view.isHidden = !open
        self.dismissOverlay.isHidden = !open
        UIAccessibility.post(notification: .screenChanged, argument: open ? self.settings.view : self.accounts.view)
      })
  }

  @objc private func close() {
    setOpen(false)
  }

  @objc private func openFromEdge(_ gesture: UIScreenEdgePanGestureRecognizer) {
    if gesture.state == .ended, gesture.translation(in: view).x > 40 {
      setOpen(true)
    }
  }
}
