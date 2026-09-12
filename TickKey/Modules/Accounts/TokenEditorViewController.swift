import SnapKit
import UIKit

/// 负责新增和编辑的表单状态，保存前由共享模型统一验证。
internal final class TokenEditorViewController: UIViewController {
  private let original: Token?
  private let isNew: Bool
  private let issuer = UITextField()
  private let account = UITextField()
  private let secret = UITextField()
  private let digits = UITextField()
  private let period = UITextField()
  private let algorithm = UISegmentedControl(items: OTPAlgorithm.allCases.map(\.rawValue))

  init(token: Token?, isNew: Bool) {
    original = token
    self.isNew = isNew
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = Localization.text(original == nil || isNew ? "add" : "edit")
    view.backgroundColor = .systemGroupedBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: Localization.text("cancel"),
      style: .plain,
      target: self,
      action: #selector(cancel))
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: Localization.text("save"),
      style: .done,
      target: self,
      action: #selector(save))
    navigationItem.rightBarButtonItem?.accessibilityIdentifier = "save-account"

    // 表单可以随键盘滚动，不依赖固定的手机屏幕高度。
    let scroll = UIScrollView()
    scroll.keyboardDismissMode = .interactive

    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 12
    view.addSubview(scroll)
    scroll.addSubview(stack)
    scroll.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
    stack.snp.makeConstraints {
      $0.edges.equalTo(scroll.contentLayoutGuide).inset(24)
      $0.width.equalTo(scroll.frameLayoutGuide).offset(-48)
    }

    for (key, field) in [
      ("issuer", issuer),
      ("account", account),
      ("secret", secret),
      ("digits", digits),
      ("period", period)
    ] {
      let label = UILabel()
      label.text = Localization.text(key)
      label.font = .preferredFont(forTextStyle: .subheadline)
      field.borderStyle = .roundedRect
      field.placeholder = Localization.text(key)
      field.accessibilityIdentifier = key
      field.autocorrectionType = .no
      field.autocapitalizationType = .none
      field.font = .preferredFont(forTextStyle: .body)
      field.snp.makeConstraints { $0.height.greaterThanOrEqualTo(44) }
      stack.addArrangedSubview(label)
      stack.addArrangedSubview(field)
    }

    let algorithmLabel = UILabel()
    algorithmLabel.text = Localization.text("algorithm")
    stack.addArrangedSubview(algorithmLabel)
    stack.addArrangedSubview(algorithm)
    populateFields()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboard(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil)
  }

  /// 恢复现有账户的字段；新账户使用常见 TOTP 默认参数。
  private func populateFields() {
    issuer.text = original?.issuer
    account.text = original?.account
    secret.text = original?.secret

    // 密钥按敏感输入处理，禁止在表单中直接展示完整字符。
    secret.isSecureTextEntry = true
    secret.textContentType = .oneTimeCode
    digits.keyboardType = .numberPad
    period.keyboardType = .numberPad
    digits.text = String(original?.digits ?? 6)
    period.text = String(original?.period ?? 30)
    algorithm.selectedSegmentIndex = OTPAlgorithm.allCases.firstIndex(of: original?.algorithm ?? .sha1) ?? 0
  }

  /// 根据键盘与当前页面的重叠区域调整滚动边距，兼容手机与 iPad 表单。
  @objc private func keyboard(_ note: Notification) {
    guard let scroll = view.subviews.first as? UIScrollView,
          let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
      return
    }

    let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY - view.safeAreaInsets.bottom)
    scroll.contentInset.bottom = overlap
    scroll.verticalScrollIndicatorInsets.bottom = overlap
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    if original == nil {
      issuer.becomeFirstResponder()
    }
  }

  @objc private func cancel() {
    dismiss(animated: true)
  }

  /// 先构造有效账户，再区分新增和编辑；失败时保留表单供用户修改。
  @objc private func save() {
    do {
      let token = try Token(
        id: original?.id ?? UUID(),
        issuer: issuer.text ?? "",
        account: account.text ?? "",
        secret: secret.text ?? "",
        algorithm: OTPAlgorithm.allCases[algorithm.selectedSegmentIndex],
        digits: Int(digits.text ?? "") ?? 0,
        period: Int(period.text ?? "") ?? 0)

      if original != nil, !isNew {
        try AppModel.shared.update(token)
      } else {
        let result = try AppModel.shared.add([token])

        if result.duplicates > 0 {
          throw TickKeyError.duplicate
        }
      }
      dismiss(animated: true)
    } catch {
      showError(error)
    }
  }
}
