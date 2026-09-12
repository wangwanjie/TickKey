import AppKit
import Combine
import SnapKit

// MARK: - MacAccountsViewController

/// 管理原生 Mac 账户列表，按窗口宽度调整卡片列数。
internal final class MacAccountsViewController: NSViewController, NSSearchFieldDelegate {
  private let sidebar = MacAppearanceBackgroundView(color: .controlBackgroundColor)
  private let header = NSView()
  private let scroll = NSScrollView()
  private let canvas = NSView()
  private let search = NSSearchField()
  private let heading = NSTextField(labelWithString: "")
  private let summary = NSTextField(labelWithString: "")
  private let empty = NSTextField(wrappingLabelWithString: "")
  private var cards: [MacTokenCard] = []
  private var subscriptions = Set<AnyCancellable>()
  private var sidebarLabels: [(NSTextField, String)] = []
  private var buttons: [(NSButton, String)] = []
  private lazy var transfer = MacTransferCoordinator(presenter: self)
  private var editor: MacTokenEditor?
  private var selecting = false
  private var selection = AccountSelection()
  private var shown: [Token] = []
  private var selectionButtons: [(NSButton, String)] = []
  private var normalButtons: [NSButton] = []

  override func loadView() {
    view = MacAppearanceBackgroundView(color: .windowBackgroundColor)
    view.frame = NSRect(x: 0, y: 0, width: 1040, height: 720)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.wantsLayer = true
    sidebar.wantsLayer = true
    [sidebar, header, scroll].forEach(view.addSubview)
    sidebar.snp.makeConstraints {
      $0.leading.top.bottom.equalToSuperview()
      $0.width.equalTo(210)
    }
    header.snp.makeConstraints {
      $0.leading.equalTo(sidebar.snp.trailing)
      $0.top.trailing.equalToSuperview()
      $0.height.equalTo(184)
    }
    scroll.snp.makeConstraints {
      $0.leading.equalTo(sidebar.snp.trailing)
      $0.top.equalTo(header.snp.bottom)
      $0.trailing.bottom.equalToSuperview()
    }
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.documentView = canvas
    configureSidebar()
    configureHeader()
    observeModel()
    reload()
  }

  /// 将全局入口与本机存储说明放在侧边栏，主内容区保留给账户列表。
  private func configureSidebar() {
    let brand = NSTextField(labelWithString: "◈  TickKey")
    brand.font = .systemFont(ofSize: 25, weight: .bold)
    sidebar.addSubview(brand)
    brand.snp.makeConstraints {
      $0.top.equalToSuperview().offset(34)
      $0.leading.equalToSuperview().offset(24)
    }

    let local = NSTextField(wrappingLabelWithString: "")
    local.font = .systemFont(ofSize: 12)
    local.textColor = .secondaryLabelColor
    sidebar.addSubview(local)
    local.snp.makeConstraints {
      $0.top.equalTo(brand.snp.bottom).offset(12)
      $0.leading.trailing.equalToSuperview().inset(24)
    }
    sidebarLabels.append((local, "local"))

    let all = NSTextField(labelWithString: "")
    all.font = .systemFont(ofSize: 14, weight: .semibold)
    sidebar.addSubview(all)
    all.snp.makeConstraints {
      $0.top.equalTo(local.snp.bottom).offset(44)
      $0.leading.trailing.equalToSuperview().inset(24)
    }
    sidebarLabels.append((all, "all.accounts"))

    let privacy = NSTextField(wrappingLabelWithString: "")
    privacy.font = .systemFont(ofSize: 12)
    privacy.textColor = .secondaryLabelColor
    sidebar.addSubview(privacy)
    privacy.snp.makeConstraints {
      $0.leading.trailing.equalToSuperview().inset(24)
      $0.bottom.equalToSuperview().inset(28)
    }
    sidebarLabels.append((privacy, "privacy"))

    let settings = NSButton(title: "", target: self, action: #selector(showSettings))
    settings.bezelStyle = .rounded
    sidebar.addSubview(settings)
    settings.snp.makeConstraints {
      $0.leading.equalToSuperview().offset(24)
      $0.bottom.equalTo(privacy.snp.top).offset(-24)
    }
    buttons.append((settings, "settings"))
  }

  /// 组织搜索和批量操作入口，并为窄窗口限制标题与按钮之间的间距。
  private func configureHeader() {
    heading.font = .systemFont(ofSize: 26, weight: .bold)
    summary.font = .systemFont(ofSize: 12)
    summary.textColor = .secondaryLabelColor
    [heading, summary, search].forEach(header.addSubview)
    heading.snp.makeConstraints {
      $0.top.equalToSuperview().offset(26)
      $0.leading.equalToSuperview().offset(28)
    }
    summary.snp.makeConstraints {
      $0.top.equalTo(heading.snp.bottom).offset(8)
      $0.leading.equalTo(heading)
    }
    search.delegate = self
    search.sendsSearchStringImmediately = true
    search.snp.makeConstraints {
      $0.leading.equalTo(heading)
      $0.trailing.equalToSuperview().inset(28)
      $0.bottom.equalToSuperview().inset(12)
      $0.height.equalTo(28)
    }

    configureActions()
    heading.snp.makeConstraints { $0.trailing.lessThanOrEqualToSuperview().inset(28) }
    empty.alignment = .center
    empty.font = .systemFont(ofSize: 18)
    empty.textColor = .secondaryLabelColor
    canvas.addSubview(empty)
  }

  /// 将普通操作和多选操作放在独立一行，窄窗口中不挤压标题。
  private func configureActions() {
    let actions = NSStackView()
    actions.spacing = 8

    for (key, selector) in [
      ("import", #selector(importAccounts)),
      ("export", #selector(exportAccounts)),
      ("add", #selector(addAccount)),
      ("selection.start", #selector(toggleSelection))
    ] {
      let button = NSButton(title: "", target: self, action: selector)
      button.bezelStyle = .rounded
      button.identifier = NSUserInterfaceItemIdentifier(key)
      actions.addArrangedSubview(button)
      buttons.append((button, key))
      normalButtons.append(button)
    }
    for (key, selector) in [
      ("select.all", #selector(selectAllAccounts)),
      ("selection.invert", #selector(invertSelection)),
      ("delete", #selector(deleteSelected)),
      ("cancel", #selector(toggleSelection))
    ] {
      let button = NSButton(title: "", target: self, action: selector)
      button.bezelStyle = .rounded
      button.identifier = NSUserInterfaceItemIdentifier("selection." + key)
      actions.addArrangedSubview(button)
      selectionButtons.append((button, key))
    }
    header.addSubview(actions)
    actions.snp.makeConstraints {
      $0.leading.equalTo(heading)
      $0.trailing.lessThanOrEqualToSuperview().inset(28)
      $0.top.equalTo(summary.snp.bottom).offset(12)
    }
  }

  /// 订阅账户和偏好变化；定时刷新只处理可见卡片，减少大列表的绘制成本。
  private func observeModel() {
    AppModel.shared
      .$tokens
      .sink { [weak self] _ in DispatchQueue.main.async { self?.reload() } }
      .store(in: &subscriptions)
    AppModel.shared.$preferences.sink { [weak self] _ in self?.localize() }.store(in: &subscriptions)
    Timer.publish(every: 1.0 / 30, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        guard let self, view.window?.isVisible == true else {
          return
        }
        cards.filter { $0.frame.intersects(self.canvas.visibleRect) }.forEach { $0.tick(hidden: !NSApp.isActive) }
      }
      .store(in: &subscriptions)
    NotificationCenter.default
      .publisher(for: NSApplication.didResignActiveNotification)
      .sink { [weak self] _ in self?.cards.forEach { $0.tick(hidden: true) } }
      .store(in: &subscriptions)
  }

  override func viewDidAppear() {
    super.viewDidAppear()

    if let error = AppModel.shared.startupError {
      MacAlerts.error(error)
    }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    arrangeCards()
  }

  func controlTextDidChange(_ obj: Notification) {
    reload()
  }

  private func localize() {
    heading.stringValue = Localization.text("accounts")
    search.placeholderString = Localization.text("search")
    sidebarLabels.forEach { $0.0.stringValue = Localization.text($0.1) }
    buttons.forEach { $0.0.title = Localization.text($0.1) }
    selectionButtons.forEach { $0.0.title = Localization.text($0.1) }
    reload()
  }

  /// 按搜索条件重建卡片，闭包通过弱引用回到控制器，避免卡片反向持有页面。
  private func reload() {
    cards.forEach { $0.removeFromSuperview() }
    shown = AppModel.shared.tokens.filter { $0.matches(search.stringValue) }
    selection.retainVisible(shown)
    cards = shown.map { token in
      let card = MacTokenCard(token: token)
      card.onToggleSelection = { [weak self] in
        self?.selection.toggle(token.id)
        self?.updateSelectionControls()
      }
      card.onEdit = { [weak self] in self?.edit(token) }
      card.onQR = { [weak self] in self?.transfer.showQR([token]) }
      card.onDelete = {
        if MacAlerts.confirm(Localization.text("delete.warning")) {
          do {
            try AppModel.shared.delete(token)
          } catch {
            MacAlerts.error(error)
          }
        }
      }
      canvas.addSubview(card)

      return card
    }
    empty.stringValue = Localization
      .text(AppModel.shared.tokens.isEmpty ? "empty.title" : "empty.search") + "\n\n" + Localization
      .text("empty.body")
    empty.isHidden = !cards.isEmpty
    updateSelectionControls()
    arrangeCards()
  }

  private func updateSelectionControls() {
    summary.stringValue = selecting
      ? String(format: Localization.text("selection.scope"), selection.ids.count)
      : Localization.text("subtitle")
    normalButtons.forEach { $0.isHidden = selecting }
    normalButtons.last?.isEnabled = !shown.isEmpty
    for (button, key) in selectionButtons {
      button.isHidden = !selecting
      button.isEnabled = key == "cancel" || (key == "delete" ? !selection.ids.isEmpty : !shown.isEmpty)
      if key == "delete" {
        button.contentTintColor = .systemRed
      }
    }
    cards.forEach { $0.setSelectionMode(selecting, selected: selection.ids.contains($0.token.id)) }
  }

  @objc private func toggleSelection() {
    selecting.toggle()
    selection = AccountSelection()
    updateSelectionControls()
  }

  @objc private func selectAllAccounts() {
    selection.selectAll(in: shown)
    updateSelectionControls()
  }

  @objc private func invertSelection() {
    selection.invert(in: shown)
    updateSelectionControls()
  }

  @objc private func deleteSelected() {
    guard let request = selection.deletion(in: shown), let window = view.window else {
      return
    }
    presentDeletionConfirmation(request, final: false, window: window)
  }

  /// 分两张独立警告面板确认高风险删除；取消任意一层都保留选择与账户。
  private func presentDeletionConfirmation(_ request: AccountDeletion, final: Bool, window: NSWindow) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = Localization.text(final ? "selection.delete.final" : "selection.delete")
    alert.informativeText = final ? request.finalWarning : request.warning
    let cancel = alert.addButton(withTitle: Localization.text("cancel"))
    cancel.keyEquivalent = "\r"
    let needsAnother = request.requiresSecondConfirmation && !final
    let confirm = alert.addButton(withTitle: Localization.text(needsAnother ? "continue" : "selection.delete.confirm"))
    confirm.keyEquivalent = ""
    confirm.hasDestructiveAction = true
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertSecondButtonReturn, let self else {
        return
      }
      if needsAnother {
        presentDeletionConfirmation(request, final: true, window: window)
      } else {
        do {
          try AppModel.shared.delete(ids: request.ids)
          toggleSelection()
        } catch {
          MacAlerts.error(error)
        }
      }
    }
  }

  /// 以最小卡片宽度计算列数，文档高度至少填满视口，以保持空态与滚动布局稳定。
  private func arrangeCards() {
    let width = scroll.contentSize.width
    // 窗口变窄时减少列数，卡片之间保持固定间距。
    let columns = max(1, Int((width - 40 + 16) / 310))
    let cardWidth = floor((width - 48 - CGFloat(columns - 1) * 16) / CGFloat(columns))
    let rows = Int(ceil(Double(cards.count) / Double(columns)))
    let height = max(scroll.contentSize.height, CGFloat(rows) * 176 + 24)
    canvas.frame = NSRect(x: 0, y: 0, width: width, height: height)

    for (index, card) in cards.enumerated() {
      card.frame = NSRect(
        x: 24 + CGFloat(index % columns) * (cardWidth + 16),
        y: height - 16 - CGFloat(index / columns + 1) * 176 + 16,
        width: cardWidth,
        height: 160)
    }
    empty.frame = NSRect(x: 30, y: max(20, height / 2 - 70), width: max(100, width - 60), height: 160)
  }

  @objc func addAccount() {
    guard !selecting else {
      return
    }
    edit(nil)
  }

  @objc func importAccounts() {
    guard !selecting else {
      return
    }
    transfer.chooseImport()
  }

  @objc func exportAccounts() {
    guard !selecting else {
      return
    }
    transfer.chooseExport()
  }

  @objc private func showSettings() {
    (NSApp.delegate as? MacAppDelegate)?.showPreferences()
  }

  private func edit(_ token: Token?) {
    let editor = MacTokenEditor(token: token)
    self.editor = editor
    presentAsSheet(editor)
  }
}

// MARK: - MacAppearanceBackgroundView

/// 动态颜色必须在视图当前外观中解析；外观变化主动使图层失效，无需等待窗口缩放。
internal final class MacAppearanceBackgroundView: NSView {
  private let color: NSColor

  init(color: NSColor) {
    self.color = color
    super.init(frame: .zero)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var wantsUpdateLayer: Bool {
    true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func updateLayer() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = color.cgColor
    }
  }
}
