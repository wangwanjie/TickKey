import UIKit
import Combine
import SnapKit

final class AccountsViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating {
    private let model = AppModel.shared
    private let search = UISearchController(searchResultsController: nil)
    private let layout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let empty = UIStackView(), emptyTitle = UILabel(), emptyBody = UILabel()
    private var subscriptions = Set<AnyCancellable>()
    private var shown: [Token] = []
    private lazy var transfer = IOSTransferCoordinator(presenter: self)
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationController?.navigationBar.prefersLargeTitles = true
        search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        collection.backgroundColor = .clear
        collection.dataSource = self; collection.delegate = self
        collection.alwaysBounceVertical = true
        collection.register(TokenCell.self, forCellWithReuseIdentifier: TokenCell.reuseID)
        view.addSubview(collection)
        collection.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        let icon = UIImageView(image: UIImage(systemName: "lock.shield")); icon.contentMode = .scaleAspectFit; icon.tintColor = view.tintColor
        icon.snp.makeConstraints { $0.height.equalTo(66) }
        empty.axis = .vertical; empty.spacing = 16; empty.alignment = .fill
        emptyTitle.font = .preferredFont(forTextStyle: .title2)
        emptyBody.font = .preferredFont(forTextStyle: .body); emptyBody.textColor = .secondaryLabel
        [emptyTitle, emptyBody].forEach { $0.numberOfLines = 0; $0.textAlignment = .center; $0.adjustsFontForContentSizeCategory = true }
        [icon, emptyTitle, emptyBody].forEach(empty.addArrangedSubview)
        view.addSubview(empty)
        empty.snp.makeConstraints { $0.center.equalTo(view.safeAreaLayoutGuide); $0.leading.greaterThanOrEqualToSuperview().offset(32); $0.trailing.lessThanOrEqualToSuperview().offset(-32); $0.width.lessThanOrEqualTo(400) }
        model.$tokens.sink { [weak self] _ in DispatchQueue.main.async { self?.reload() } }.store(in: &subscriptions)
        model.$preferences.sink { [weak self] _ in self?.localize() }.store(in: &subscriptions)
        Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard self?.view.window != nil, UIApplication.shared.applicationState == .active else { return }
            self?.collection.visibleCells.compactMap { $0 as? TokenCell }.forEach { $0.tick() }
        }.store(in: &subscriptions)
        reload()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let error = model.startupError { showError(error) }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layout.invalidateLayout() }
    private func localize() {
        title = "TickKey"; search.searchBar.placeholder = L.text("search")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(settings))
        navigationItem.leftBarButtonItem?.accessibilityLabel = L.text("settings")
        navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add)),
            UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(exportMenu))]
        navigationItem.rightBarButtonItems?[0].accessibilityIdentifier = "add-account"
        navigationItem.rightBarButtonItems?[1].accessibilityLabel = L.text("export")
        reload()
    }
    func updateSearchResults(for searchController: UISearchController) { reload() }
    private func reload() {
        shown = model.tokens.filter { $0.matches(search.searchBar.text ?? "") }
        collection.reloadData(); empty.isHidden = !shown.isEmpty
        emptyTitle.text = L.text(model.tokens.isEmpty ? "empty.title" : "empty.search")
        emptyBody.text = L.text(model.tokens.isEmpty ? "empty.body" : "search")
    }
    @objc private func add() {
        let sheet = UIAlertController(title: L.text("add"), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L.text("manual"), style: .default) { [weak self] _ in self?.edit(nil) })
        #if !targetEnvironment(macCatalyst)
        sheet.addAction(UIAlertAction(title: L.text("scan"), style: .default) { [weak self] _ in
            guard let self else { return }
            let scanner = ScannerViewController { [weak self] token in self?.edit(token, isNew: true) }
            self.present(UINavigationController(rootViewController: scanner), animated: true)
        })
        #endif
        sheet.addAction(UIAlertAction(title: L.text("import"), style: .default) { [weak self] _ in self?.transfer.chooseImport() })
        sheet.addAction(UIAlertAction(title: L.text("cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(sheet, animated: true)
    }
    @objc private func exportMenu() { transfer.chooseExport(anchor: navigationItem.rightBarButtonItems?.last) }
    @objc private func settings() {
        let controller = SettingsViewController()
        controller.modalPresentationStyle = .custom
        controller.transitioningDelegate = controller
        present(controller, animated: true)
    }
    private func edit(_ token: Token?, isNew: Bool = false) {
        present(UINavigationController(rootViewController: TokenEditorViewController(token: token, isNew: isNew)), animated: true)
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { shown.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TokenCell.reuseID, for: indexPath) as! TokenCell
        let token = shown[indexPath.item]; cell.configure(token)
        cell.onMore = { [weak self, weak cell] in self?.itemMenu(token, source: cell) }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width - 40
        let columns = max(1, Int((width + 16) / 330))
        return CGSize(width: floor((width - CGFloat(columns - 1) * 16) / CGFloat(columns)), height: 160 + max(0, UIFont.preferredFont(forTextStyle: .headline).pointSize - 17) * 2)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets { UIEdgeInsets(top: 18, left: 20, bottom: 24, right: 20) }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat { 16 }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat { 16 }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        do {
            let code = try TOTP.code(for: shown[indexPath.item])
            UIPasteboard.general.setItems([["public.utf8-plain-text": code]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(30)])
            UIAccessibility.post(notification: .announcement, argument: L.text("copied"))
            navigationItem.prompt = L.text("copied")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.navigationItem.prompt = nil }
        } catch { showError(error) }
    }
    private func itemMenu(_ token: Token, source: UIView?) {
        let sheet = UIAlertController(title: token.title, message: token.account, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L.text("edit"), style: .default) { [weak self] _ in self?.edit(token) })
        sheet.addAction(UIAlertAction(title: L.text("qr"), style: .default) { [weak self] _ in self?.transfer.showQR([token]) })
        sheet.addAction(UIAlertAction(title: L.text("delete"), style: .destructive) { [weak self] _ in
            self?.confirm(title: L.text("delete"), message: L.text("delete.warning"), destructive: true) {
                do { try self?.model.delete(token) } catch { self?.showError(error) }
            }
        })
        sheet.addAction(UIAlertAction(title: L.text("cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = source ?? view
        sheet.popoverPresentationController?.sourceRect = source?.bounds ?? view.bounds
        present(sheet, animated: true)
    }
}

extension UIViewController {
    func showError(_ error: Error) { showMessage(error.localizedDescription, title: L.text("error")) }
    func showMessage(_ message: String, title: String = "TickKey") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.text("close"), style: .default)); present(alert, animated: true)
    }
    func confirm(title: String, message: String, destructive: Bool = false, action: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L.text("continue"), style: destructive ? .destructive : .default) { _ in action() })
        present(alert, animated: true)
    }
}
