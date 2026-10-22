import AppKit
import SnapKit

/// 覆盖主窗口内容的锁定界面；拦截鼠标和键盘事件，只保留解锁入口。
internal final class MacLockView: NSView {
  var onUnlock: (() -> Void)?
  private let title = NSTextField(labelWithString: "")
  private let message = NSTextField(wrappingLabelWithString: "")
  private let unlock = NSButton()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setAccessibilityIdentifier("lock-overlay")

    let icon = NSImageView()
    icon.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)
    icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 52, weight: .regular)
    icon.contentTintColor = NSColor(named: "AccentColor") ?? .controlAccentColor
    title.font = .systemFont(ofSize: 22, weight: .bold)
    title.alignment = .center
    message.font = .systemFont(ofSize: 13)
    message.textColor = .secondaryLabelColor
    message.alignment = .center
    unlock.bezelStyle = .rounded
    unlock.controlSize = .large
    unlock.keyEquivalent = "\r"
    unlock.target = self
    unlock.action = #selector(unlockTapped)

    let stack = NSStackView(views: [icon, title, message, unlock])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 14
    stack.setCustomSpacing(24, after: message)
    addSubview(stack)
    stack.snp.makeConstraints {
      $0.center.equalToSuperview()
      $0.width.lessThanOrEqualTo(380)
    }
    localize()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var wantsUpdateLayer: Bool {
    true
  }

  /// 不透明背景在当前外观中解析，确保锁定时看不到下面的验证码。
  override func updateLayer() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  /// 锁定期间吞掉点击、滚动和按键，避免事件传到下层卡片触发复制。
  override func mouseDown(with event: NSEvent) {}

  override func rightMouseDown(with event: NSEvent) {}

  override func scrollWheel(with event: NSEvent) {}

  override func keyDown(with event: NSEvent) {}

  func localize() {
    title.stringValue = Localization.text("lock.title")
    message.stringValue = Localization.text("lock.body")
    unlock.title = Localization.text("lock.unlock")
  }

  /// 验证失败时在锁定界面内显示原因，不额外弹窗。
  func show(_ error: Error) {
    message.stringValue = error.localizedDescription
  }

  @objc private func unlockTapped() {
    onUnlock?()
  }
}
