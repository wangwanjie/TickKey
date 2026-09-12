import AppKit
import Combine
import SnapKit

/// 提供固定宽度的偏好设置窗口，各标签页通过滚动容器适配内容。
internal final class PreferencesWindowController: NSWindowController {
  private let tabs = NSSegmentedControl()
  private let scroll = NSScrollView()
  private let stack = NSStackView()
  private var observation: AnyCancellable?
  private let content = NSView()

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    super.init(window: window)
    window.isReleasedWhenClosed = false
    window.center()
    window.contentView = content
    tabs.segmentCount = 3
    tabs.selectedSegment = 0
    tabs.target = self
    tabs.action = #selector(tabChanged)
    content.addSubview(tabs)
    content.addSubview(scroll)
    tabs.snp.makeConstraints {
      $0.top.equalToSuperview().offset(20)
      $0.centerX.equalToSuperview()
    }
    scroll.snp.makeConstraints {
      $0.top.equalTo(tabs.snp.bottom).offset(24)
      $0.leading.trailing.bottom.equalToSuperview().inset(24)
    }
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 20
    let document = NSView()
    scroll.documentView = document
    document.addSubview(stack)
    document.snp.makeConstraints {
      $0.width.equalTo(scroll.contentView)
      $0.height.greaterThanOrEqualTo(230)
    }
    stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(8) }

    // @Published 在赋值前发出事件；切到下一轮主线程后读取新的偏好。
    observation = AppModel.shared.$preferences.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuild() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func tabChanged() {
    rebuild()
    resize(animated: true)
  }

  /// 切换标签时保持窗口顶边位置，动画调整高度，避免标签栏跳动。
  private func resize(animated: Bool) {
    guard let window else {
      return
    }

    let height: CGFloat = [360, 310, 340][tabs.selectedSegment]
    let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 500, height: height))
    var frame = window.frame
    frame.origin.y += frame.height - target.height
    frame.size = target.size
    window.setFrame(frame, display: true, animate: animated)
  }

  private func label(_ value: String) {
    let field = NSTextField(wrappingLabelWithString: value)
    field.isSelectable = true
    stack.addArrangedSubview(field)
    field.snp.makeConstraints { $0.width.equalTo(stack) }
  }

  /// 按当前标签生成内容，偏好写入完成后再读取新值，避免选中状态落后一拍。
  private func rebuild() {
    window?.title = Localization.text("settings")

    for item in ["appearance", "updates", "about"].enumerated() {
      tabs.setLabel(
        Localization.text(item.element),
        forSegment: item.offset)
    }
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

    switch tabs.selectedSegment {
    case 0:
      label(Localization.text("appearance"))

      let theme = NSPopUpButton()
      theme.addItems(withTitles: [Localization.text("system"), Localization.text("light"), Localization.text("dark")])
      theme.selectItem(at: AppModel.shared.preferences.appearance)
      theme.target = self
      theme.action = #selector(themeChanged(_:))
      stack.addArrangedSubview(theme)
      label(Localization.text("language"))

      let language = NSPopUpButton()
      language.addItems(withTitles: [Localization.text("system"), "简体中文", "繁體中文", "English"])
      language
        .selectItem(at: ["system", "zh-Hans", "zh-Hant", "en"]
          .firstIndex(of: AppModel.shared.preferences.language) ?? 0)
      language.target = self
      language.action = #selector(languageChanged(_:))
      stack.addArrangedSubview(language)
    case 1:
      label(Localization.text("version") + " " + AppInfo.version)

      let check = NSButton(
        title: Localization.text("check.updates"),
        target: UpdateController.shared,
        action: #selector(UpdateController.check))
      check.bezelStyle = .rounded
      stack.addArrangedSubview(check)

      if !UpdateController.shared.configured {
        label(Localization.text("updates.unconfigured"))
      }
    default:
      label("TickKey " + AppInfo.version)
      label(Localization.text("privacy"))
      label(Localization.text("local"))

      let feedback = NSButton(title: Localization.text("feedback"), target: self, action: #selector(feedback))
      feedback.bezelStyle = .rounded
      stack.addArrangedSubview(feedback)
    }
  }

  @objc private func themeChanged(_ sender: NSPopUpButton) {
    var value = AppModel.shared.preferences
    value.appearance = sender.indexOfSelectedItem

    do {
      try AppModel.shared.setPreferences(value)
    } catch {
      MacAlerts.error(error)
    }
  }

  @objc private func languageChanged(_ sender: NSPopUpButton) {
    var value = AppModel.shared.preferences
    value.language = ["system", "zh-Hans", "zh-Hant", "en"][sender.indexOfSelectedItem]

    do {
      try AppModel.shared.setPreferences(value)
    } catch {
      MacAlerts.error(error)
    }
  }

  @objc private func feedback() {
    if let url = AppInfo.issuesURL {
      NSWorkspace.shared.open(url)
    } else {
      MacAlerts.message(Localization.text("repo.unconfigured"))
    }
  }
}
