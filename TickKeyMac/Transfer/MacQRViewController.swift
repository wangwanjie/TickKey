import AppKit
import SnapKit

/// 将单个与批量二维码统一为分页表单，不向外部服务上传密钥。
internal final class MacQRViewController: NSViewController {
  private let tokens: [Token]
  private var index = 0
  private let image = NSImageView()
  private let account = NSTextField(wrappingLabelWithString: "")
  private let counter = NSTextField(labelWithString: "")
  private let previous = NSButton()
  private let next = NSButton()

  init(tokens: [Token]) {
    self.tokens = tokens
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 600))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = 20
    stack.alignment = .centerX
    view.addSubview(stack)
    stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(24) }
    account.font = .systemFont(ofSize: 16, weight: .semibold)
    account.alignment = .center
    image.imageScaling = .scaleProportionallyUpOrDown
    image.wantsLayer = true
    image.layer?.magnificationFilter = .nearest
    image.snp.makeConstraints { $0.size.equalTo(340) }
    previous.title = Localization.text("previous")
    previous.target = self
    previous.action = #selector(back)
    previous.bezelStyle = .rounded
    next.title = Localization.text("next")
    next.target = self
    next.action = #selector(forward)
    next.bezelStyle = .rounded

    let buttons = NSStackView(views: [previous, counter, next])
    buttons.spacing = 20

    let warning = NSTextField(wrappingLabelWithString: Localization.text("qr.warning"))
    warning.alignment = .center
    warning.textColor = .secondaryLabelColor

    let close = NSButton(title: Localization.text("close"), target: self, action: #selector(close))
    close.bezelStyle = .rounded
    close.keyEquivalent = "\u{1b}"
    [account, image, buttons, warning, close].forEach(stack.addArrangedSubview)
    account.snp.makeConstraints { $0.width.equalTo(stack) }
    warning.snp.makeConstraints { $0.width.equalTo(stack) }
    refresh()
  }

  /// 更新二维码、账户名称和翻页状态，首尾页面禁用相应按钮。
  private func refresh() {
    let token = tokens[index]
    account.stringValue = token.title + "\n" + token.account

    do {
      image.image = try NSImage(cgImage: QRCode.image(for: token), size: .zero)
    } catch {
      MacAlerts.error(error)
    }
    counter.stringValue = "\(index + 1) / \(tokens.count)"
    previous.isEnabled = index > 0
    next.isEnabled = index + 1 < tokens.count
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
    dismiss(self)
  }
}
