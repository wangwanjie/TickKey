import Combine
import SnapKit
import UIKit

// MARK: - AccountsViewController

/// 展示紧凑的账户列表，协调搜索、复制、左滑操作和导入导出入口。
internal final class AccountsViewController: UIViewController, UITableViewDataSource,
  UITableViewDelegate,
  UISearchResultsUpdating, UISearchBarDelegate {
  private let model = AppModel.shared
  private let search = UISearchController(searchResultsController: nil)
  private let table = UITableView(frame: .zero, style: .plain)
  private let empty = UIStackView()
  private let emptyTitle = UILabel()
  private let emptyBody = UILabel()
  private var copyHUD: UIVisualEffectView?
  private var copyHUDDismissal: AnyCancellable?
  private var subscriptions = Set<AnyCancellable>()
  private var shown: [Token] = []
  private var selecting = false
  private var filtering = false
  private var selection = AccountSelection()
  private let searchChanges = PassthroughSubject<Void, Never>()
  private var filterID = UUID()
  private var filterWork: DispatchWorkItem?
  private let filterQueue = DispatchQueue(label: "cn.vanjay.TickKey.search", qos: .userInitiated)
  private lazy var transfer = IOSTransferCoordinator(presenter: self)
  private lazy var photoImport = PhotoImportCoordinator(presenter: self)
  var onSettings: (() -> Void)?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    // 搜索栏保持在顶部，避免 iOS 26 将它整合进多选操作的底部工具栏。
    navigationController?.navigationBar.prefersLargeTitles = true
    search.searchResultsUpdater = self
    search.searchBar.delegate = self
    search.obscuresBackgroundDuringPresentation = false
    // 账户检索保留多语言输入，但不需要拼写修正和内联预测，减少输入系统的候选请求。
    search.searchBar.autocorrectionType = .no
    search.searchBar.spellCheckingType = .no
    search.searchBar.autocapitalizationType = .none
    if #available(iOS 17.0, *) {
      search.searchBar.searchTextField.inlinePredictionType = .no
    }
    if #available(iOS 16.0, *) {
      navigationItem.preferredSearchBarPlacement = .stacked
    }
    if #available(iOS 26.0, *) {
      navigationItem.searchBarPlacementAllowsToolbarIntegration = false
    }
    navigationItem.searchController = search
    navigationItem.hidesSearchBarWhenScrolling = false
    definesPresentationContext = true

    // 原生列表按内容自适应行高，并承载行内左滑菜单。
    table.backgroundColor = .clear
    table.dataSource = self
    table.delegate = self
    table.allowsMultipleSelectionDuringEditing = true
    table.rowHeight = UITableView.automaticDimension
    table.estimatedRowHeight = 84
    table.tableFooterView = UIView()
    table.register(TokenCell.self, forCellReuseIdentifier: TokenCell.reuseID)
    view.addSubview(table)
    // 滚动视图由 UIKit 调整安全区内边距，避免搜索/键盘转场的临时安全区高度产生约束冲突。
    table.snp.makeConstraints { $0.edges.equalToSuperview() }
    table.keyboardDismissMode = .onDrag

    let icon = UIImageView(image: UIImage(systemName: "lock.shield"))
    icon.contentMode = .scaleAspectFit
    icon.tintColor = view.tintColor
    icon.snp.makeConstraints { $0.height.equalTo(66) }
    empty.axis = .vertical
    empty.spacing = 16
    empty.alignment = .fill
    emptyTitle.font = .preferredFont(forTextStyle: .title2)
    emptyBody.font = .preferredFont(forTextStyle: .body)
    emptyBody.textColor = .secondaryLabel

    for item in [emptyTitle, emptyBody] {
      item.numberOfLines = 0
      item.textAlignment = .center
      item.adjustsFontForContentSizeCategory = true
    }
    [icon, emptyTitle, emptyBody].forEach(empty.addArrangedSubview)
    view.addSubview(empty)
    empty.snp.makeConstraints {
      $0.center.equalTo(view.safeAreaLayoutGuide)
      $0.leading.greaterThanOrEqualToSuperview().offset(32)
      $0.trailing.lessThanOrEqualToSuperview().offset(-32)
      $0.width.lessThanOrEqualTo(400)
    }

    bindUpdates()
    reload()
  }

  /// 发布变更后再读取模型；倒计时只更新当前可见的行。
  private func bindUpdates() {
    searchChanges
      .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
      .sink { [weak self] in self?.reload() }
      .store(in: &subscriptions)
    model.$tokens
      .sink { [weak self] _ in
        DispatchQueue.main.async {
          self?.reload()
        }
      }
      .store(in: &subscriptions)
    model.$preferences
      .sink { [weak self] _ in
        self?.localize()
      }
      .store(in: &subscriptions)
    Timer.publish(every: 1.0 / 30, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        guard self?.view.window != nil,
              self?.presentedViewController == nil || self?.presentedViewController is UISearchController,
              UIApplication.shared.applicationState == .active else {
          return
        }
        self?.table.visibleCells.compactMap { $0 as? TokenCell }.forEach { $0.tick() }
      }
      .store(in: &subscriptions)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    if let error = model.startupError {
      showError(error)
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    dismissCopyHUD()
  }

  /// 重新生成导航文案和操作入口，使语言修改立即反映到主界面。
  private func localize() {
    dismissCopyHUD()
    search.searchBar.placeholder = Localization.text("search")
    updateSelectionControls()
    reload()
  }

  func updateSearchResults(for searchController: UISearchController) {
    PerformanceDiagnostics.event("search.changed", count: model.tokens.count)
    // 输入一变化就作废旧结果，防止防抖期间回写上一个关键词的结果。
    filterID = UUID()
    filterWork?.cancel()
    filtering = true
    selection = AccountSelection()
    synchronizeSelection()
    searchChanges.send()
  }

  func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
    PerformanceDiagnostics.event("search.focus.requested")
    return true
  }

  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    PerformanceDiagnostics.event("search.focus.began")
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    searchBar.resignFirstResponder()
  }

  /// 搜索只影响当前展示列表，导出仍由协调器读取完整账户集合。
  private func reload() {
    filtering = true
    updateSelectionControls()
    let tokens = model.tokens
    let query = search.searchBar.text ?? ""
    let identifier = UUID()
    filterID = identifier
    filterWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      let result = PerformanceDiagnostics.measure("search.filter", count: tokens.count) {
        tokens.filter { $0.matches(query) }
      }
      DispatchQueue.main.async { [weak self] in
        guard let self, filterID == identifier else {
          return
        }
        applyResults(result, hasAccounts: !tokens.isEmpty)
      }
    }
    filterWork = work
    filterQueue.async(execute: work)
  }

  /// 后台筛选完成后仅在主线程更新视图，并单独记录列表刷新提交耗时。
  private func applyResults(_ result: [Token], hasAccounts: Bool) {
    PerformanceDiagnostics.measure("accounts.reload", count: result.count) {
      shown = result
      filtering = false
      selection.retainVisible(result)
      table.setEditing(selecting, animated: false)
      table.reloadData()
      synchronizeSelection()
      empty.isHidden = !shown.isEmpty
      emptyTitle.text = Localization.text(hasAccounts ? "empty.search" : "empty.title")
      emptyBody.text = Localization.text(hasAccounts ? "search" : "empty.body")
    }
  }

  /// 提供手动添加、扫码、图片与文件导入入口，并为 iPad 指定弹出锚点。
  @objc private func add() {
    PerformanceDiagnostics.event("import.menu")
    view.endEditing(true)
    let sheet = UIAlertController(title: Localization.text("add"), message: nil, preferredStyle: .actionSheet)
    sheet
      .addAction(UIAlertAction(title: Localization.text("manual"), style: .default) { [weak self] _ in
        self?.edit(nil)
      })
    #if !targetEnvironment(macCatalyst)
      sheet.addAction(UIAlertAction(title: Localization.text("scan"), style: .default) { [weak self] _ in
        guard let self else {
          return
        }

        let scanner = ScannerViewController { [weak self] token in self?.edit(token, isNew: true) }
        present(UINavigationController(rootViewController: scanner), animated: true)
      })
    #endif
    sheet.addAction(UIAlertAction(title: Localization.text("import.photos"), style: .default) { [weak self] _ in
      self?.photoImport.choosePhotos()
    })
    sheet
      .addAction(UIAlertAction(title: Localization.text("import"), style: .default) { [weak self] _ in
        self?.transfer.chooseImport()
      })
    sheet.addAction(UIAlertAction(title: Localization.text("cancel"), style: .cancel))
    sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
    present(sheet, animated: true)
  }

  @objc private func exportMenu() {
    PerformanceDiagnostics.event("export.menu")
    view.endEditing(true)
    transfer.chooseExport(anchor: navigationItem.rightBarButtonItems?[1])
  }

  @objc private func settings() {
    search.isActive = false
    view.endEditing(true)
    onSettings?()
  }

  /// 以独立导航页面编辑账户，扫码预填条目仍按新增账户保存。
  private func edit(_ token: Token?, isNew: Bool = false) {
    present(
      UINavigationController(rootViewController: TokenEditorViewController(token: token, isNew: isNew)),
      animated: true)
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    shown.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    guard let cell = tableView.dequeueReusableCell(
      withIdentifier: TokenCell.reuseID,
      for: indexPath) as? TokenCell else {
      assertionFailure("账户行的注册类型与复用类型不一致")

      return UITableViewCell()
    }

    let token = shown[indexPath.row]
    cell.configure(token)

    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    if selecting {
      selection.toggle(shown[indexPath.row].id)
      updateSelectionControls()
      return
    }
    tableView.deselectRow(at: indexPath, animated: true)
    do {
      let code = try TOTP.code(for: shown[indexPath.row])
      UIPasteboard.general.setItems(
        [["public.utf8-plain-text": code]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(30)])
      UIAccessibility.post(notification: .announcement, argument: Localization.text("copied"))
      showCopyHUD()
    } catch {
      showError(error)
    }
  }

  func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
    guard selecting else {
      return
    }
    selection.toggle(shown[indexPath.row].id)
    updateSelectionControls()
  }

  /// 将复制反馈覆盖在内容中央，不参与列表布局；连续复制只保留最新提示并重新计时。
  private func showCopyHUD() {
    dismissCopyHUD()
    let hud = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    hud.layer.cornerRadius = 18
    hud.clipsToBounds = true
    hud.isUserInteractionEnabled = false
    hud.accessibilityIdentifier = "copy-hud"
    let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    icon.tintColor = view.tintColor
    icon.contentMode = .scaleAspectFit
    icon.isAccessibilityElement = false
    icon.snp.makeConstraints { $0.size.equalTo(32) }
    let label = UILabel()
    label.text = Localization.text("copied")
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.adjustsFontForContentSizeCategory = true
    label.textAlignment = .center
    label.numberOfLines = 0
    let stack = UIStackView(arrangedSubviews: [icon, label])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 10
    hud.contentView.addSubview(stack)
    stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(20) }
    view.addSubview(hud)
    hud.snp.makeConstraints {
      $0.center.equalTo(view.safeAreaLayoutGuide)
      $0.leading.greaterThanOrEqualTo(view.safeAreaLayoutGuide).offset(24)
      $0.trailing.lessThanOrEqualTo(view.safeAreaLayoutGuide).offset(-24)
      $0.width.lessThanOrEqualTo(280)
    }
    copyHUD = hud
    copyHUDDismissal = Just(())
      .delay(for: .seconds(2), scheduler: DispatchQueue.main)
      .sink { [weak self] _ in self?.dismissCopyHUD() }
  }

  private func dismissCopyHUD() {
    copyHUDDismissal?.cancel()
    copyHUDDismissal = nil
    copyHUD?.removeFromSuperview()
    copyHUD = nil
  }

  /// 使用系统行内操作并禁用整段滑动直接执行，删除仍需独立确认。
  func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    guard !selecting else {
      return nil
    }
    let token = shown[indexPath.row]
    let edit = UIContextualAction(style: .normal, title: Localization.text("edit")) { [weak self] _, _, done in
      done(true)
      self?.edit(token)
    }
    edit.image = UIImage(systemName: "pencil")
    edit.backgroundColor = view.tintColor
    let qr = UIContextualAction(style: .normal, title: Localization.text("qr")) { [weak self] _, _, done in
      done(true)
      self?.transfer.showQR([token])
    }
    qr.image = UIImage(systemName: "qrcode")
    qr.backgroundColor = .systemGray
    let delete = UIContextualAction(style: .normal, title: Localization.text("delete")) { [weak self] _, _, done in
      // 此操作只打开确认框，使用普通完成流程，避免系统提前进入删除行的过渡状态。
      done(true)
      self?.confirm(
        title: Localization.text("delete"),
        message: Localization.text("delete.warning"),
        destructive: true) {
          do {
            try self?.model.delete(token)
          } catch {
            self?.showError(error)
          }
        }
    }
    delete.image = UIImage(systemName: "trash")
    delete.backgroundColor = .systemRed
    let configuration = UISwipeActionsConfiguration(actions: [delete, qr, edit])
    configuration.performsFirstActionWithFullSwipe = false
    return configuration
  }
}

/// 集中处理多选状态及批量删除的分步确认。
extension AccountsViewController {
  /// 多选模式只提供选择和删除入口，底部工具栏适应窄屏。
  private func updateSelectionControls() {
    title = selecting ? String(format: Localization.text("selection.count"), selection.ids.count) : "TickKey"
    navigationItem.prompt = selecting ? Localization.text("selection.hint") : nil
    navigationController?.setToolbarHidden(!selecting, animated: false)
    if selecting {
      navigationItem.leftBarButtonItem = UIBarButtonItem(
        title: Localization.text("cancel"), style: .plain, target: self, action: #selector(toggleSelection))
      navigationItem.rightBarButtonItems = []
      let all = UIBarButtonItem(
        title: Localization.text("select.all"), style: .plain, target: self, action: #selector(selectAllAccounts))
      all.accessibilityIdentifier = "select-all-accounts"
      let invert = UIBarButtonItem(
        title: Localization.text("selection.invert"), style: .plain, target: self, action: #selector(invertSelection))
      invert.accessibilityIdentifier = "invert-account-selection"
      let delete = UIBarButtonItem(
        title: Localization.text("delete"), style: .plain, target: self, action: #selector(deleteSelected))
      delete.tintColor = .systemRed
      delete.isEnabled = !filtering && !selection.ids.isEmpty
      delete.accessibilityIdentifier = "delete-selected-accounts"
      all.isEnabled = !filtering && !shown.isEmpty
      invert.isEnabled = !filtering && !shown.isEmpty
      toolbarItems = [all, .flexibleSpace(), invert, .flexibleSpace(), delete]
      return
    }
    toolbarItems = nil
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "gearshape"),
      style: .plain,
      target: self,
      action: #selector(settings))
    navigationItem.leftBarButtonItem?.accessibilityLabel = Localization.text("settings")
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add)),
      UIBarButtonItem(
        image: UIImage(systemName: "square.and.arrow.up"),
        style: .plain,
        target: self,
        action: #selector(exportMenu)),
      UIBarButtonItem(
        image: UIImage(systemName: "checkmark.circle"),
        style: .plain,
        target: self,
        action: #selector(toggleSelection))
    ]
    navigationItem.rightBarButtonItems?[0].accessibilityIdentifier = "add-account"
    navigationItem.rightBarButtonItems?[1].accessibilityLabel = Localization.text("export")
    navigationItem.rightBarButtonItems?[2].accessibilityLabel = Localization.text("selection.start")
    navigationItem.rightBarButtonItems?[2].accessibilityIdentifier = "select-accounts"
    navigationItem.rightBarButtonItems?[2].isEnabled = !filtering && !shown.isEmpty
  }

  @objc private func toggleSelection() {
    view.endEditing(true)
    search.isActive = false
    dismissCopyHUD()
    selecting.toggle()
    selection = AccountSelection()
    table.setEditing(selecting, animated: true)
    synchronizeSelection()
  }

  @objc private func selectAllAccounts() {
    guard !filtering else {
      return
    }
    selection.selectAll(in: shown)
    synchronizeSelection()
  }

  @objc private func invertSelection() {
    guard !filtering else {
      return
    }
    selection.invert(in: shown)
    synchronizeSelection()
  }

  private func synchronizeSelection() {
    for (row, token) in shown.enumerated() {
      let path = IndexPath(row: row, section: 0)
      if selecting, selection.ids.contains(token.id) {
        table.selectRow(at: path, animated: false, scrollPosition: .none)
      } else {
        table.deselectRow(at: path, animated: false)
      }
    }
    updateSelectionControls()
  }

  @objc private func deleteSelected() {
    guard !filtering, let request = selection.deletion(in: shown) else {
      return
    }
    presentDeletionConfirmation(request, final: false)
  }

  /// 第一层完全关闭后再展示第二层；只有最后一次确认才提交固定的删除集合。
  private func presentDeletionConfirmation(_ request: AccountDeletion, final: Bool) {
    let alert = UIAlertController(
      title: Localization.text(final ? "selection.delete.final" : "selection.delete"),
      message: final ? request.finalWarning : request.warning,
      preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: Localization.text("cancel"), style: .cancel))
    let needsAnother = request.requiresSecondConfirmation && !final
    alert.addAction(UIAlertAction(
      title: Localization.text(needsAnother ? "continue" : "selection.delete.confirm"),
      style: .destructive) { [weak self, weak alert] _ in
        alert?.dismiss(animated: true) { [weak self] in
          guard let self else {
            return
          }
          if needsAnother {
            presentDeletionConfirmation(request, final: true)
          } else {
            do {
              try model.delete(ids: request.ids)
              toggleSelection()
            } catch {
              showError(error)
            }
          }
        }
      })
    let presenter: UIViewController = search.isActive ? search : self
    presenter.present(alert, animated: true)
  }
}

/// 统一轻量提示和确认交互，避免在各业务入口重复配置弹窗。
extension UIViewController {
  func showError(_ error: Error) {
    showMessage(error.localizedDescription, title: Localization.text("error"))
  }

  func showMessage(_ message: String, title: String = "TickKey") {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: Localization.text("close"), style: .default))
    present(alert, animated: true)
  }

  func confirm(title: String, message: String, destructive: Bool = false, action: @escaping () -> Void) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: Localization.text("cancel"), style: .cancel))
    alert
      .addAction(UIAlertAction(
        title: Localization.text("continue"),
        style: destructive ? .destructive : .default) { _ in
          action()
        })
    present(alert, animated: true)
  }
}
