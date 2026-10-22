import Combine
import UIKit

// MARK: - SettingsSection

/// 设置分组，枚举顺序即界面上的显示顺序。
private enum SettingsSection: Int, CaseIterable {
  case appearance
  case language
  case security
  case about

  var titleKey: String {
    switch self {
    case .appearance:
      "appearance"
    case .language:
      "language"
    case .security:
      "security"
    case .about:
      "about"
    }
  }
}

// MARK: - SettingsViewController

/// 以系统分组列表呈现设置，偏好保存后整表刷新，保证文案和选中状态来自同一次设置。
internal final class SettingsViewController: UITableViewController {
  var onClose: (() -> Void)?
  private var observation: AnyCancellable?
  /// 语言偏好的存储值，与界面行一一对应。
  private let languages = ["system", "zh-Hans", "zh-Hant", "en"]

  init() {
    super.init(style: .insetGrouped)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.largeTitleDisplayMode = .always
    let close = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(done))
    close.accessibilityIdentifier = "close-settings"
    navigationItem.rightBarButtonItem = close

    // 等待 @Published 赋值完成再刷新，保证读取到的是新的偏好。
    observation = AppModel.shared.$preferences.receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }
  }

  private func reload() {
    title = Localization.text("settings")
    navigationItem.rightBarButtonItem?.accessibilityLabel = Localization.text("close")
    tableView.reloadData()
  }

  // MARK: 数据源

  override func numberOfSections(in tableView: UITableView) -> Int {
    SettingsSection.allCases.count
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch SettingsSection(rawValue: section) {
    case .appearance:
      3
    case .language:
      languages.count
    case .security:
      1
    case .about:
      2
    case nil:
      0
    }
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    SettingsSection(rawValue: section).map { Localization.text($0.titleKey) }
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    switch SettingsSection(rawValue: section) {
    case .security:
      Localization.text("lock.setting.help")
    case .about:
      Localization.text("privacy") + "\n" + Localization.text("local")
    default:
      nil
    }
  }

  /// 行数很少且类型各异，直接创建单元格，避免复用时残留开关或勾选状态。
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let preferences = AppModel.shared.preferences

    switch SettingsSection(rawValue: indexPath.section) {
    case .appearance:
      let titles = [Localization.text("system"), Localization.text("light"), Localization.text("dark")]
      return optionCell(titles[indexPath.row], selected: preferences.appearance == indexPath.row)
    case .language:
      // 语言名称使用各自的母语书写，任何界面语言下都能找到自己的语言。
      let titles = [Localization.text("system"), "简体中文", "繁體中文", "English"]
      return optionCell(titles[indexPath.row], selected: preferences.language == languages[indexPath.row])
    case .security:
      return securityCell(isOn: preferences.requiresUnlock)
    case .about:
      return indexPath.row == 0 ? versionCell() : feedbackCell()
    case nil:
      return UITableViewCell()
    }
  }

  // MARK: 单元格

  private func optionCell(_ title: String, selected: Bool) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    var content = cell.defaultContentConfiguration()
    content.text = title
    cell.contentConfiguration = content
    cell.accessoryType = selected ? .checkmark : .none
    if selected {
      cell.accessibilityTraits.insert(.selected)
    }
    return cell
  }

  /// 解锁保护开关；切换前由系统验证身份，取消或失败时刷新列表恢复原状态。
  private func securityCell(isOn: Bool) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    var content = cell.defaultContentConfiguration()
    content.text = Localization.text("lock.setting")
    cell.contentConfiguration = content
    cell.selectionStyle = .none

    let toggle = UISwitch()
    toggle.isOn = isOn
    toggle.accessibilityIdentifier = "require-unlock"
    toggle.accessibilityLabel = content.text
    toggle.addTarget(self, action: #selector(lockChanged(_:)), for: .valueChanged)
    cell.accessoryView = toggle
    return cell
  }

  private func versionCell() -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    var content = UIListContentConfiguration.valueCell()
    content.text = Localization.text("version")
    content.secondaryText = AppInfo.version
    cell.contentConfiguration = content
    cell.selectionStyle = .none
    return cell
  }

  /// 反馈入口会离开应用打开浏览器，用外链图标提示跳转。
  private func feedbackCell() -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    var content = cell.defaultContentConfiguration()
    content.text = Localization.text("feedback")
    content.textProperties.color = .tintColor
    cell.contentConfiguration = content

    let icon = UIImageView(image: UIImage(systemName: "arrow.up.right"))
    icon.tintColor = .tertiaryLabel
    cell.accessoryView = icon
    cell.accessibilityTraits.insert(.link)
    return cell
  }

  // MARK: 交互

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)

    var value = AppModel.shared.preferences
    switch SettingsSection(rawValue: indexPath.section) {
    case .appearance:
      value.appearance = indexPath.row
    case .language:
      value.language = languages[indexPath.row]
    case .about:
      if indexPath.row == 1 {
        openFeedback()
      }
      return
    default:
      return
    }

    guard value != AppModel.shared.preferences else {
      return
    }

    do {
      try AppModel.shared.setPreferences(value)
    } catch {
      showError(error)
    }
  }

  @objc private func lockChanged(_ sender: UISwitch) {
    AppLock.shared.setRequiresUnlock(sender.isOn) { [weak self] error in
      if let error {
        self?.showError(error)
      }
      self?.reload()
    }
  }

  @objc private func done() {
    onClose?()
  }

  private func openFeedback() {
    guard let url = AppInfo.issuesURL else {
      showMessage(Localization.text("repo.unconfigured"))
      return
    }
    UIApplication.shared.open(url)
  }

  override func accessibilityPerformEscape() -> Bool {
    onClose?()
    return true
  }
}
