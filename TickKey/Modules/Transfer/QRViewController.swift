import SnapKit
import UIKit

/// 逐页显示完整大小的账户二维码，供其他验证器连续扫码。
internal final class QRViewController: UIViewController {
  private let tokens: [Token]
  private var index = 0
  private let image = UIImageView()
  private let account = UILabel()
  private let counter = UILabel()
  private let previous = UIButton(type: .system)
  private let nextButton = UIButton(type: .system)

  init(tokens: [Token]) {
    self.tokens = tokens
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    title = Localization.text("qr.batch")
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: Localization.text("close"),
      style: .done,
      target: self,
      action: #selector(close))

    let scroll = UIScrollView()

    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 20
    stack.alignment = .center
    view.addSubview(scroll)
    scroll.addSubview(stack)
    scroll.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
    stack.snp.makeConstraints {
      $0.edges.equalTo(scroll.contentLayoutGuide).inset(24)
      $0.width.equalTo(scroll.frameLayoutGuide).offset(-48)
    }
    account.numberOfLines = 0
    account.textAlignment = .center
    account.font = .preferredFont(forTextStyle: .headline)
    image.contentMode = .scaleAspectFit
    image.layer.magnificationFilter = .nearest
    image.snp.makeConstraints {
      $0.width.equalTo(stack).priority(750)
      $0.width.lessThanOrEqualTo(360)
      $0.height.equalTo(image.snp.width)
    }

    let warning = UILabel()
    warning.text = Localization.text("qr.warning")
    warning.numberOfLines = 0
    warning.textColor = .secondaryLabel
    warning.textAlignment = .center
    previous.setTitle(Localization.text("previous"), for: .normal)
    nextButton.setTitle(Localization.text("next"), for: .normal)
    previous.addTarget(self, action: #selector(back), for: .touchUpInside)
    nextButton.addTarget(self, action: #selector(forward), for: .touchUpInside)

    let buttons = UIStackView(arrangedSubviews: [previous, counter, nextButton])
    buttons.spacing = 24
    [account, image, buttons, warning].forEach(stack.addArrangedSubview)
    refresh()
  }

  /// 同步当前账户、二维码与页码，并禁止越过首尾页面。
  private func refresh() {
    account.text = tokens[index].title + "\n" + tokens[index].account

    do {
      image.image = try UIImage(cgImage: QRCode.image(for: tokens[index]))
    } catch {
      showError(error)
    }
    counter.text = "\(index + 1) / \(tokens.count)"
    previous.isEnabled = index > 0
    nextButton.isEnabled = index + 1 < tokens.count
  }

  @objc private func back() {
    index -= 1
    refresh()
  }

  @objc private func forward() {
    index += 1
    refresh()
  }

  @objc private func close() {
    dismiss(animated: true)
  }
}
