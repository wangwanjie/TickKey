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
  private var subscriptions = Set<AnyCancellable>()
  private var shown: [Token] = []
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

    // 系统搜索栏在 iPhone 与 iPad 上自动采用合适的位置。
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
    navigationItem.searchController = search
    navigationItem.hidesSearchBarWhenScrolling = false
    definesPresentationContext = true

    // 原生列表按内容自适应行高，并承载行内左滑菜单。
    table.backgroundColor = .clear
    table.dataSource = self
    table.delegate = self
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

  /// 重新生成导航文案和操作入口，使语言修改立即反映到主界面。
  private func localize() {
    title = "TickKey"
    search.searchBar.placeholder = Localization.text("search")
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
        action: #selector(exportMenu))
    ]
    navigationItem.rightBarButtonItems?[0].accessibilityIdentifier = "add-account"
    navigationItem.rightBarButtonItems?[1].accessibilityLabel = Localization.text("export")
    reload()
  }

  func updateSearchResults(for searchController: UISearchController) {
    PerformanceDiagnostics.event("search.changed", count: model.tokens.count)
    // 输入一变化就作废旧结果，防止防抖期间回写上一个关键词的结果。
    filterID = UUID()
    filterWork?.cancel()
    searchChanges.send()
  }

  func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
    PerformanceDiagnostics.event("search.focus.requested")
    return true
  }

  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    PerformanceDiagnostics.event("search.focus.began")
  }

  /// 搜索只影响当前展示列表，导出仍由协调器读取完整账户集合。
  private func reload() {
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
      table.setEditing(false, animated: false)
      table.reloadData()
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
    transfer.chooseExport(anchor: navigationItem.rightBarButtonItems?.last)
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
    tableView.deselectRow(at: indexPath, animated: true)
    do {
      let code = try TOTP.code(for: shown[indexPath.row])
      UIPasteboard.general.setItems(
        [["public.utf8-plain-text": code]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(30)])
      UIAccessibility.post(notification: .announcement, argument: Localization.text("copied"))
      navigationItem.prompt = Localization.text("copied")
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.navigationItem.prompt = nil }
    } catch {
      showError(error)
    }
  }

  /// 使用系统行内操作并禁用整段滑动直接执行，删除仍需独立确认。
  func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
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
