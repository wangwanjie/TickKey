import Combine
import SnapKit
import UIKit

// MARK: - AccountsViewController

/// 展示自适应账户卡片，协调搜索、复制、编辑和导入导出入口。
internal final class AccountsViewController: UIViewController, UICollectionViewDataSource,
  UICollectionViewDelegateFlowLayout,
  UISearchResultsUpdating {
  private let model = AppModel.shared
  private let search = UISearchController(searchResultsController: nil)
  private let layout = UICollectionViewFlowLayout()
  private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
  private let empty = UIStackView()
  private let emptyTitle = UILabel()
  private let emptyBody = UILabel()
  private var subscriptions = Set<AnyCancellable>()
  private var shown: [Token] = []
  private lazy var transfer = IOSTransferCoordinator(presenter: self)
  private lazy var photoImport = PhotoImportCoordinator(presenter: self)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground

    // 系统搜索栏在 iPhone 与 iPad 上自动采用合适的位置。
    navigationController?.navigationBar.prefersLargeTitles = true
    search.searchResultsUpdater = self
    search.obscuresBackgroundDuringPresentation = false
    navigationItem.searchController = search
    navigationItem.hidesSearchBarWhenScrolling = false
    definesPresentationContext = true

    // 卡片网格只展示筛选后的账户，条目原始数据由 AppModel 持有。
    collection.backgroundColor = .clear
    collection.dataSource = self
    collection.delegate = self
    collection.alwaysBounceVertical = true
    collection.register(TokenCell.self, forCellWithReuseIdentifier: TokenCell.reuseID)
    view.addSubview(collection)
    collection.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }

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

    // 发布变更后再读取模型；倒计时只更新当前可见的卡片。
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
        guard self?.view.window != nil, UIApplication.shared.applicationState == .active else {
          return
        }
        self?.collection.visibleCells.compactMap { $0 as? TokenCell }.forEach { $0.tick() }
      }
      .store(in: &subscriptions)
    reload()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    if let error = model.startupError {
      showError(error)
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layout.invalidateLayout()
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
    reload()
  }

  /// 搜索只影响当前展示列表，导出仍由协调器读取完整账户集合。
  private func reload() {
    shown = model.tokens.filter { $0.matches(search.searchBar.text ?? "") }
    collection.reloadData()
    empty.isHidden = !shown.isEmpty
    emptyTitle.text = Localization.text(model.tokens.isEmpty ? "empty.title" : "empty.search")
    emptyBody.text = Localization.text(model.tokens.isEmpty ? "empty.body" : "search")
  }

  /// 提供手动添加、扫码、图片与文件导入入口，并为 iPad 指定弹出锚点。
  @objc private func add() {
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
    transfer.chooseExport(anchor: navigationItem.rightBarButtonItems?.last)
  }

  @objc private func settings() {
    let controller = SettingsViewController()
    controller.modalPresentationStyle = .custom
    controller.transitioningDelegate = controller
    present(controller, animated: true)
  }

  /// 以独立导航页面编辑账户，扫码预填条目仍按新增账户保存。
  private func edit(_ token: Token?, isNew: Bool = false) {
    present(
      UINavigationController(rootViewController: TokenEditorViewController(token: token, isNew: isNew)),
      animated: true)
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    shown.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    guard let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: TokenCell.reuseID,
      for: indexPath) as? TokenCell else {
      assertionFailure("账户卡片的注册类型与复用类型不一致")

      return UICollectionViewCell()
    }

    let token = shown[indexPath.item]
    cell.configure(token)
    cell.onMore = { [weak self, weak cell] in self?.itemMenu(token, source: cell) }

    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath) -> CGSize {
    let width = collectionView.bounds.width - 40
    let columns = max(1, Int((width + 16) / 330))

    return CGSize(
      width: floor((width - CGFloat(columns - 1) * 16) / CGFloat(columns)),
      height: 160 + max(0, UIFont.preferredFont(forTextStyle: .headline).pointSize - 17) * 2)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int) -> UIEdgeInsets {
    UIEdgeInsets(top: 18, left: 20, bottom: 24, right: 20)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    minimumLineSpacingForSectionAt section: Int) -> CGFloat {
    16
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
    16
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    do {
      let code = try TOTP.code(for: shown[indexPath.item])
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

  /// 管理单个账户的编辑、二维码和删除操作，删除前提示登录恢复风险。
  private func itemMenu(_ token: Token, source: UIView?) {
    let sheet = UIAlertController(title: token.title, message: token.account, preferredStyle: .actionSheet)
    sheet
      .addAction(UIAlertAction(title: Localization.text("edit"), style: .default) { [weak self] _ in
        self?.edit(token)
      })
    sheet
      .addAction(UIAlertAction(title: Localization.text("qr"), style: .default) { [weak self] _ in
        self?.transfer.showQR([token])
      })
    sheet.addAction(UIAlertAction(title: Localization.text("delete"), style: .destructive) { [weak self] _ in
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
    })
    sheet.addAction(UIAlertAction(title: Localization.text("cancel"), style: .cancel))
    sheet.popoverPresentationController?.sourceView = source ?? view
    sheet.popoverPresentationController?.sourceRect = source?.bounds ?? view.bounds
    present(sheet, animated: true)
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
