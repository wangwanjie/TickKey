import AppKit
import SnapKit

/// 以窗口附属表单编辑账户，使用共享验证规则处理名称缺失和重复条目。
internal final class MacTokenEditor: NSViewController {
  private let original: Token?
  private let issuer = NSTextField()
  private let account = NSTextField()
  private let secret = NSSecureTextField()
  private let digits = NSTextField()
  private let period = NSTextField()
  private let algorithm = NSPopUpButton()

  init(token: Token?) {
    original = token
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 560))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    view.addSubview(stack)
    stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(28) }

    let title = NSTextField(labelWithString: Localization.text(original == nil ? "add" : "edit"))
    title.font = .systemFont(ofSize: 22, weight: .bold)
    stack.addArrangedSubview(title)

    for (key, field) in [
      ("issuer", issuer),
      ("account", account),
      ("secret", secret as NSTextField),
      ("digits", digits),
      ("period", period)
    ] {
      stack.addArrangedSubview(NSTextField(labelWithString: Localization.text(key)))
      field.placeholderString = Localization.text(key)
      field.identifier = NSUserInterfaceItemIdentifier(key)
      stack.addArrangedSubview(field)
      field.snp.makeConstraints { $0.width.equalTo(stack) }
    }
    stack.addArrangedSubview(NSTextField(labelWithString: Localization.text("algorithm")))
    algorithm.addItems(withTitles: OTPAlgorithm.allCases.map(\.rawValue))
    stack.addArrangedSubview(algorithm)
    issuer.stringValue = original?.issuer ?? ""
    account.stringValue = original?.account ?? ""
    secret.stringValue = original?.secret ?? ""
    digits.stringValue = String(original?.digits ?? 6)
    period.stringValue = String(original?.period ?? 30)
    algorithm.selectItem(withTitle: (original?.algorithm ?? .sha1).rawValue)

    let cancel = NSButton(title: Localization.text("cancel"), target: self, action: #selector(cancel))
    cancel.bezelStyle = .rounded
    cancel.keyEquivalent = "\u{1b}"

    let save = NSButton(title: Localization.text("save"), target: self, action: #selector(save))
    save.bezelStyle = .rounded
    save.keyEquivalent = "\r"

    let actions = NSStackView(views: [cancel, save])
    actions.spacing = 12
    stack.addArrangedSubview(actions)
  }

  @objc private func cancel() {
    dismiss(self)
  }

  /// 只在模型验证和持久化均成功后关闭表单，失败时保留用户输入。
  @objc private func save() {
    do {
      let token = try Token(
        id: original?.id ?? UUID(),
        issuer: issuer.stringValue,
        account: account.stringValue,
        secret: secret.stringValue,
        algorithm: OTPAlgorithm.allCases[algorithm.indexOfSelectedItem],
        digits: Int(digits.stringValue) ?? 0,
        period: Int(period.stringValue) ?? 0)

      if original == nil {
        if try AppModel.shared.add([token]).duplicates > 0 {
          throw TickKeyError.duplicate
        }
      } else {
        try AppModel.shared.update(token)
      }
      dismiss(self)
    } catch {
      MacAlerts.error(error)
    }
  }
}
