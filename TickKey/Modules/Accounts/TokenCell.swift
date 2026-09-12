import SnapKit
import UIKit

/// 用紧凑的两行布局呈现账户和验证码，整行用于复制，系统承载左滑操作。
internal final class TokenCell: UITableViewCell {
  static let reuseID = "TokenCell"
  private let name = UILabel()
  private let code = UILabel()
  private let badge = UILabel()
  private let countdown = CountdownView()
  var token: Token?
  private var lastStep: Int?
  private var lastCode = "—"

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .systemBackground
    badge.textAlignment = .center
    badge.font = .systemFont(ofSize: 20, weight: .bold)
    badge.textColor = tintColor
    badge.backgroundColor = tintColor.withAlphaComponent(0.1)
    badge.layer.cornerRadius = 10
    badge.clipsToBounds = true
    name.font = UIFontMetrics(forTextStyle: .subheadline)
      .scaledFont(for: .systemFont(ofSize: 15, weight: .medium))
    name.lineBreakMode = .byTruncatingMiddle
    code.font = UIFontMetrics(forTextStyle: .title1)
      .scaledFont(for: .monospacedDigitSystemFont(ofSize: 30, weight: .semibold))
    code.textColor = tintColor
    name.adjustsFontForContentSizeCategory = true
    code.adjustsFontForContentSizeCategory = true
    countdown.backgroundColor = .clear
    [badge, name, code, countdown].forEach(contentView.addSubview)
    badge.snp.makeConstraints {
      $0.leading.equalTo(contentView.safeAreaLayoutGuide).offset(20)
      $0.centerY.equalToSuperview()
      $0.size.equalTo(40)
    }
    name.snp.makeConstraints {
      $0.leading.equalTo(badge.snp.trailing).offset(12)
      $0.top.equalToSuperview().inset(12)
      $0.trailing.equalTo(contentView.safeAreaLayoutGuide).inset(20)
    }
    code.snp.makeConstraints {
      $0.leading.equalTo(name)
      $0.top.equalTo(name.snp.bottom).offset(4)
      $0.bottom.equalToSuperview().inset(12)
      $0.trailing.lessThanOrEqualTo(countdown.snp.leading).offset(-8)
    }
    countdown.snp.makeConstraints {
      $0.trailing.equalTo(name)
      $0.centerY.equalTo(code)
      $0.size.equalTo(24)
    }
    code.adjustsFontSizeToFitWidth = true
    separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 20)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// 复用到新账户时清除验证码缓存，避免显示上一个账户的结果。
  func configure(_ token: Token) {
    self.token = token
    lastStep = nil
    name.text = token.displayName
    name.accessibilityLabel = token.displayName
    badge.text = String(token.title.prefix(1)).uppercased()
    accessibilityIdentifier = "token-" + token.account
    tick()
  }

  /// 动画每帧更新，但仅在周期变化时重新计算 HMAC，降低持续刷新开销。
  func tick() {
    guard let token else {
      return
    }

    let step = Int(Date().timeIntervalSince1970 / Double(token.period))

    if step != lastStep {
      lastStep = step
      lastCode = (try? TOTP.code(for: token)).map(TOTP.display) ?? "—"
      code.text = lastCode
    }
    countdown.fraction = TOTP.remainingFraction(for: token)
    let remaining = String(Int(ceil(countdown.fraction * Double(token.period)))) + " s"
    if countdown.accessibilityLabel != remaining {
      countdown.accessibilityLabel = remaining
    }
  }
}
