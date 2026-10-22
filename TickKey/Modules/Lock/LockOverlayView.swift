import SnapKit
import UIKit

/// 覆盖整个窗口的锁定界面，只提供解锁入口，不显示任何账户信息。
internal final class LockOverlayView: UIView {
  var onUnlock: (() -> Void)?
  private let message = UILabel()
  private let unlock = UIButton(type: .system)
  private let title = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .systemBackground
    accessibilityIdentifier = "lock-overlay"

    let icon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
    icon.contentMode = .scaleAspectFit
    icon.tintColor = UIColor(named: "AccentColor")
    icon.snp.makeConstraints { $0.height.equalTo(64) }
    title.font = .preferredFont(forTextStyle: .title2)
    title.adjustsFontForContentSizeCategory = true
    title.textAlignment = .center
    title.numberOfLines = 0
    message.font = .preferredFont(forTextStyle: .body)
    message.adjustsFontForContentSizeCategory = true
    message.textColor = .secondaryLabel
    message.textAlignment = .center
    message.numberOfLines = 0

    // 解锁按钮使用醒目的填充样式，取消验证后用户可以随时再次发起。
    var configuration = UIButton.Configuration.filled()
    configuration.cornerStyle = .large
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 32, bottom: 12, trailing: 32)
    unlock.configuration = configuration
    unlock.accessibilityIdentifier = "unlock-app"
    unlock.addTarget(self, action: #selector(unlockTapped), for: .touchUpInside)

    let stack = UIStackView(arrangedSubviews: [icon, title, message, unlock])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 16
    stack.setCustomSpacing(28, after: message)
    addSubview(stack)
    stack.snp.makeConstraints {
      $0.center.equalTo(safeAreaLayoutGuide)
      $0.leading.greaterThanOrEqualTo(safeAreaLayoutGuide).offset(32)
      $0.trailing.lessThanOrEqualTo(safeAreaLayoutGuide).offset(-32)
    }
    localize()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// 每次上锁重新读取文案，使语言切换后锁屏界面同样生效。
  func localize() {
    title.text = Localization.text("lock.title")
    message.text = Localization.text("lock.body")
    unlock.configuration?.title = Localization.text("lock.unlock")
  }

  /// 验证失败时在锁屏内显示原因，不额外弹窗遮挡解锁按钮。
  func show(_ error: Error) {
    message.text = error.localizedDescription
  }

  @objc private func unlockTapped() {
    onUnlock?()
  }
}
