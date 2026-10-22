import AppKit
import Combine
import SnapKit

// MARK: - PreferencePane

/// 偏好设置的标签页，原始值同时作为工具栏标识和文案键。
private enum PreferencePane: String, CaseIterable {
  case general
  case updates
  case about

  var identifier: NSToolbarItem.Identifier {
    NSToolbarItem.Identifier(rawValue)
  }

  var symbol: String {
    switch self {
    case .general:
      "gearshape"
    case .updates:
      "arrow.triangle.2.circlepath"
    case .about:
      "info.circle"
    }
  }
}

// MARK: - PreferencesWindowController

/// 采用系统偏好设置样式的工具栏标签窗口，切换标签时按内容高度动画调整窗口。
internal final class PreferencesWindowController: NSWindowController, NSToolbarDelegate {
  private static let width: CGFloat = 480
  /// 表单左右两列固定宽度，各标签页的冒号和控件起点保持对齐，说明文字按右列宽度换行。
  private static let labelWidth: CGFloat = 130
  private static let fieldWidth: CGFloat = 290
  /// 下拉菜单统一宽度，不同语言下选项文字长短不一也保持整齐。
  private static let popUpWidth: CGFloat = 160
  private var pane = PreferencePane.general
  private var observation: AnyCancellable?

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 240),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    super.init(window: window)
    window.isReleasedWhenClosed = false

    let toolbar = NSToolbar(identifier: "preferences")
    toolbar.delegate = self
    toolbar.displayMode = .iconAndLabel
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .preference
    toolbar.selectedItemIdentifier = pane.identifier

    rebuild(animated: false)
    window.center()

    // @Published 在赋值前发出事件；切到下一轮主线程后读取新的偏好。
    observation = AppModel.shared.$preferences.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
      self?.rebuild(animated: false)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: 工具栏

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    PreferencePane.allCases.map(\.identifier)
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    PreferencePane.allCases.map(\.identifier)
  }

  func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    PreferencePane.allCases.map(\.identifier)
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool)
    -> NSToolbarItem? {
    guard let pane = PreferencePane(rawValue: itemIdentifier.rawValue) else {
      return nil
    }

    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    item.label = Localization.text(pane.rawValue)
    item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil)
    item.target = self
    item.action = #selector(selectPane(_:))
    return item
  }

  @objc private func selectPane(_ sender: NSToolbarItem) {
    guard let selected = PreferencePane(rawValue: sender.itemIdentifier.rawValue), selected != pane else {
      return
    }
    pane = selected
    rebuild(animated: true)
  }

  // MARK: 内容

  /// 重新生成当前标签内容并刷新工具栏文案，偏好变化后选中状态和语言即时同步。
  private func rebuild(animated: Bool) {
    guard let window else {
      return
    }

    window.title = Localization.text(pane.rawValue)
    // 显式同步工具栏选中项，通过辅助功能或代码切换标签时高亮也能跟随内容。
    window.toolbar?.selectedItemIdentifier = pane.identifier
    for item in window.toolbar?.items ?? [] {
      if let itemPane = PreferencePane(rawValue: item.itemIdentifier.rawValue) {
        item.label = Localization.text(itemPane.rawValue)
      }
    }

    let body: NSView = switch pane {
    case .general:
      generalPane()
    case .updates:
      updatesPane()
    case .about:
      aboutPane()
    }

    // 底边约束低于窗口保持尺寸的优先级，窗口缩放动画过程中不会与内容约束冲突。
    let container = NSView()
    container.addSubview(body)
    container.snp.makeConstraints { $0.width.equalTo(Self.width) }
    body.snp.makeConstraints {
      $0.top.equalToSuperview().offset(24)
      $0.centerX.equalToSuperview()
      $0.bottom.equalToSuperview().offset(-24).priority(490)
    }
    let size = container.fittingSize
    window.contentView = container
    resize(window, to: size, animated: animated)
  }

  /// 保持窗口顶边位置调整高度，避免切换标签时工具栏跳动。
  private func resize(_ window: NSWindow, to size: NSSize, animated: Bool) {
    let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
    var frame = window.frame
    frame.origin.y += frame.height - target.height
    frame.size = target.size
    window.setFrame(frame, display: true, animate: animated && window.isVisible)
  }

  /// 外观、语言和解锁保护，使用标签右对齐的系统表单布局。
  private func generalPane() -> NSView {
    let preferences = AppModel.shared.preferences

    let theme = NSPopUpButton()
    theme.addItems(withTitles: [Localization.text("system"), Localization.text("light"), Localization.text("dark")])
    theme.selectItem(at: preferences.appearance)
    theme.target = self
    theme.action = #selector(themeChanged(_:))

    // 语言名称使用各自的母语书写，任何界面语言下都能找到自己的语言。
    let language = NSPopUpButton()
    language.addItems(withTitles: [Localization.text("system"), "简体中文", "繁體中文", "English"])
    language.selectItem(at: ["system", "zh-Hans", "zh-Hant", "en"].firstIndex(of: preferences.language) ?? 0)
    language.target = self
    language.action = #selector(languageChanged(_:))

    let lock = NSButton(
      checkboxWithTitle: Localization.text("lock.setting"),
      target: self,
      action: #selector(lockChanged(_:)))
    lock.state = preferences.requiresUnlock ? .on : .off

    for popUp in [theme, language] {
      popUp.snp.makeConstraints { $0.width.equalTo(Self.popUpWidth) }
    }

    let grid = NSGridView(views: [
      [formLabel("appearance"), theme],
      [formLabel("language"), language],
      [formLabel("security"), lock],
      [NSGridCell.emptyContentView, note(Localization.text("lock.setting.help"))]
    ])
    configure(grid)
    // 选项之间保持常规间距，安全设置额外拉开分组，说明文字紧贴所属的复选框。
    grid.rowSpacing = 6
    grid.row(at: 1).topPadding = 6
    grid.row(at: 2).topPadding = 16
    return grid
  }

  /// 以横跨窗口的卡片展示当前版本，检查更新按钮靠右与版本信息同行，未配置发布源时在卡片下方说明。
  private func updatesPane() -> NSView {
    let icon = NSImageView(image: NSApp.applicationIconImage)
    icon.snp.makeConstraints { $0.width.height.equalTo(40) }

    let name = NSTextField(labelWithString: "TickKey")
    name.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    let version = NSTextField(labelWithString: Localization.text("version") + " " + AppInfo.version)
    version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    version.textColor = .secondaryLabelColor
    let info = NSStackView(views: [name, version])
    info.orientation = .vertical
    info.alignment = .leading
    info.spacing = 2

    let check = NSButton(
      title: Localization.text("check.updates"),
      target: UpdateController.shared,
      action: #selector(UpdateController.check))
    check.bezelStyle = .rounded

    // 图标和版本信息靠左，按钮放在尾部区域，窗口宽度变化时按钮始终贴右。
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    row.setViews([icon, info], in: .leading)
    row.setViews([check], in: .trailing)

    // 使用 NSBox 填充色，外观切换时背景随系统颜色自动更新。
    let card = NSBox()
    card.boxType = .custom
    card.titlePosition = .noTitle
    card.borderWidth = 0
    card.cornerRadius = 10
    card.fillColor = NSColor.labelColor.withAlphaComponent(0.05)
    card.contentViewMargins = .zero
    card.contentView?.addSubview(row)
    row.snp
      .makeConstraints { $0.edges.equalToSuperview().inset(NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)) }
    card.snp.makeConstraints { $0.width.equalTo(Self.width - 48) }

    let stack = NSStackView(views: [card])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    if !UpdateController.shared.configured {
      let hint = NSTextField(wrappingLabelWithString: Localization.text("updates.unconfigured"))
      hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      hint.textColor = .secondaryLabelColor
      hint.preferredMaxLayoutWidth = Self.width - 48
      stack.addArrangedSubview(hint)
    }
    return stack
  }

  /// 居中展示应用图标、版本、隐私承诺和反馈入口。
  private func aboutPane() -> NSView {
    let icon = NSImageView(image: NSApp.applicationIconImage)
    icon.snp.makeConstraints { $0.width.height.equalTo(64) }

    let name = NSTextField(labelWithString: "TickKey")
    name.font = .systemFont(ofSize: 17, weight: .semibold)

    let version = NSTextField(labelWithString: Localization.text("version") + " " + AppInfo.version)
    version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    version.textColor = .secondaryLabelColor

    let privacy = NSTextField(wrappingLabelWithString: Localization.text("privacy"))
    let local = NSTextField(wrappingLabelWithString: Localization.text("local"))
    local.textColor = .secondaryLabelColor
    for field in [privacy, local] {
      field.alignment = .center
      field.preferredMaxLayoutWidth = Self.width - 80
    }

    let feedback = NSButton(title: Localization.text("feedback"), target: self, action: #selector(feedback))
    feedback.bezelStyle = .rounded

    let stack = NSStackView(views: [icon, name, version, privacy, local, feedback])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 4
    stack.setCustomSpacing(10, after: icon)
    stack.setCustomSpacing(14, after: version)
    stack.setCustomSpacing(18, after: local)
    return stack
  }

  private func configure(_ grid: NSGridView) {
    grid.rowSpacing = 12
    grid.columnSpacing = 8
    grid.rowAlignment = .firstBaseline
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 0).width = Self.labelWidth
    grid.column(at: 1).xPlacement = .leading
    grid.column(at: 1).width = Self.fieldWidth
  }

  private func formLabel(_ key: String) -> NSTextField {
    NSTextField(labelWithString: String(format: Localization.text("label.format"), Localization.text(key)))
  }

  /// 表单右列的辅助说明，按固定宽度换行，计算窗口高度时即可得到正确行数。
  private func note(_ value: String) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: value)
    field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    field.textColor = .secondaryLabelColor
    field.preferredMaxLayoutWidth = Self.fieldWidth
    field.snp.makeConstraints { $0.width.equalTo(Self.fieldWidth) }
    return field
  }

  // MARK: 交互

  @objc private func lockChanged(_ sender: NSButton) {
    AppLock.shared.setRequiresUnlock(sender.state == .on) { [weak self] error in
      if let error {
        MacAlerts.error(error)
      }
      self?.rebuild(animated: false)
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
