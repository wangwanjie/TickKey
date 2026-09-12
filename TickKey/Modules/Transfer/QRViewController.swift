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
  private let activity = UIActivityIndicatorView(style: .medium)
  private let renderQueue = DispatchQueue(label: "cn.vanjay.TickKey.qr", qos: .userInitiated)
  private var renderID = UUID()

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
    // 先建立共同父视图，再激活跨视图约束，否则 UIKit 会抛出 NSGenericException。
    image.snp.makeConstraints {
      $0.width.equalTo(stack).priority(750)
      $0.width.lessThanOrEqualTo(360)
      $0.height.equalTo(image.snp.width)
    }
    image.addSubview(activity)
    activity.snp.makeConstraints { $0.center.equalToSuperview() }
    image.accessibilityIdentifier = "export-qr-image"
    previous.accessibilityIdentifier = "previous-qr"
    nextButton.accessibilityIdentifier = "next-qr"
    previous.isEnabled = false
    nextButton.isEnabled = false
    activity.startAnimating()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    PerformanceDiagnostics.event("qr.visible")
    // 先让页面转场完成，再首次初始化 Core Image，避免与 UIKit 转场竞争系统资源。
    refresh()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    renderID = UUID()
  }

  /// 同步当前账户、二维码与页码，并禁止越过首尾页面。
  private func refresh() {
    guard tokens.indices.contains(index) else {
      previous.isEnabled = false
      nextButton.isEnabled = false
      return
    }
    let token = tokens[index]
    account.text = token.title + "\n" + token.account
    image.image = nil
    activity.startAnimating()
    let identifier = UUID()
    renderID = identifier
    renderQueue.async { [weak self] in
      let result = Result {
        try PerformanceDiagnostics.measure("qr.render") { try QRCode.image(for: token) }
      }
      DispatchQueue.main.async { [weak self] in
        guard let self, renderID == identifier else {
          return
        }
        activity.stopAnimating()
        do {
          image.image = try UIImage(cgImage: result.get())
          PerformanceDiagnostics.event("qr.displayed")
        } catch {
          // 首次生成可能早于页面展示完成，直接在当前页面反馈，不叠加弹窗。
          account.text = error.localizedDescription
        }
      }
    }
    counter.text = "\(index + 1) / \(tokens.count)"
    previous.isEnabled = index > 0
    nextButton.isEnabled = index + 1 < tokens.count
  }

  @objc private func back() {
    guard index > 0 else {
      return
    }
    index -= 1
    refresh()
  }

  @objc private func forward() {
    guard index + 1 < tokens.count else {
      return
    }
    index += 1
    refresh()
  }

  @objc private func close() {
    dismiss(animated: true)
  }
}
