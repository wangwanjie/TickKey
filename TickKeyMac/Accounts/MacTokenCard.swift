import AppKit
import SnapKit

/// 处理单个账户的显示、键盘操作和复制反馈，验证码与倒计时分别更新。
internal final class MacTokenCard: NSView {
  let token: Token
  var onEdit: (() -> Void)?
  var onQR: (() -> Void)?
  var onDelete: (() -> Void)?
  private let code = NSTextField(labelWithString: "")
  private let issuer = NSTextField(labelWithString: "")
  private let account = NSTextField(labelWithString: "")
  private let pie = MacCountdownView()
  private let more = NSButton()
  private var copiedUntil = Date.distantPast
  private var lastStep: Int?
  private var lastCode = "—"

  init(token: Token) {
    self.token = token
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 18
    layer?.borderWidth = 1
    issuer.stringValue = token.title
    issuer.font = .systemFont(ofSize: 15, weight: .semibold)
    account.stringValue = token.account
    account.font = .systemFont(ofSize: 12)
    account.textColor = .secondaryLabelColor
    code.font = .monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
    [issuer, account, code, pie, more].forEach(addSubview)
    issuer.lineBreakMode = .byTruncatingTail
    account.lineBreakMode = .byTruncatingMiddle
    more.title = "•••"
    more.bezelStyle = .inline
    more.target = self
    more.action = #selector(showMenu)
    more.setAccessibilityLabel(Localization.text("edit") + " " + token.account)
    issuer.snp.makeConstraints {
      $0.leading.top.equalToSuperview().inset(20)
      $0.trailing.lessThanOrEqualTo(more.snp.leading).offset(-6)
    }
    account.snp.makeConstraints {
      $0.leading.trailing.equalTo(issuer)
      $0.top.equalTo(issuer.snp.bottom).offset(6)
    }
    more.snp.makeConstraints {
      $0.trailing.top.equalToSuperview().inset(12)
      $0.width.equalTo(32)
    }
    code.snp.makeConstraints {
      $0.leading.equalTo(issuer)
      $0.bottom.equalToSuperview().inset(20)
      $0.trailing.lessThanOrEqualTo(pie.snp.leading).offset(-8)
    }
    pie.snp.makeConstraints {
      $0.trailing.bottom.equalToSuperview().inset(22)
      $0.size.equalTo(26)
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(token.title + ", " + token.account + ", " + Localization.text("copy"))
    tick(hidden: false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func accessibilityPerformPress() -> Bool {
    copyCode()

    return true
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    copyCode()
  }

  override func keyDown(with event: NSEvent) {
    if event.characters == " " || event.keyCode == 36 {
      copyCode()
    } else {
      super.keyDown(with: event)
    }
  }

  @objc func copy(_ sender: Any?) {
    copyCode()
  }

  /// 复制时重新计算当前验证码，30 秒后仅清理尚未被其他应用改写的剪贴板。
  private func copyCode() {
    do {
      let value = try TOTP.code(for: token)
      let board = NSPasteboard.general
      board.clearContents()
      board.setString(value, forType: .string)

      // changeCount 不变才说明剪贴板仍属于本次复制，不清理后来复制的其他内容。
      let change = board.changeCount
      DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        if board.changeCount == change {
          board.clearContents()
        }
      }
      copiedUntil = Date().addingTimeInterval(2)
      tick(hidden: false)
    } catch {
      MacAlerts.error(error)
    }
  }

  /// 按周期缓存验证码，失去活动状态时立即遮挡数字。
  func tick(hidden: Bool) {
    let step = Int(Date().timeIntervalSince1970 / Double(token.period))

    if !hidden && lastStep != step {
      lastStep = step
      lastCode = (try? TOTP.code(for: token)).map(TOTP.display) ?? "—"
    }
    code.stringValue = hidden ? "••• •••" : lastCode
    account.stringValue = Date() < copiedUntil ? Localization.text("copied") : token.account
    pie.fraction = TOTP.remainingFraction(for: token)
    let accent = NSColor(named: "AccentColor") ?? .controlAccentColor
    code.textColor = accent
    layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
  }

  @objc private func showMenu() {
    let menu = NSMenu()

    for (key, action) in [("edit", #selector(edit)), ("qr", #selector(qr)), ("delete", #selector(deleteToken))] {
      let item = NSMenuItem(title: Localization.text(key), action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    menu.popUp(positioning: nil, at: NSPoint(x: more.frame.minX, y: more.frame.minY), in: self)
  }

  @objc private func edit() {
    onEdit?()
  }

  @objc private func qr() {
    onQR?()
  }

  @objc private func deleteToken() {
    onDelete?()
  }
}
