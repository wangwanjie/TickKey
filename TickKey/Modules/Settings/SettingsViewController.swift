import Combine
import SnapKit
import UIKit

// MARK: - SettingsViewController

/// 提供侧边抽屉设置，保存偏好后同步刷新控件和界面文案。
internal final class SettingsViewController: UIViewController {
  var onClose: (() -> Void)?
  private let stack = UIStackView()
  private var observation: AnyCancellable?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground

    let scroll = UIScrollView()
    view.addSubview(scroll)
    scroll.addSubview(stack)
    scroll.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
    stack.axis = .vertical
    stack.spacing = 20
    stack.snp.makeConstraints {
      $0.edges.equalTo(scroll.contentLayoutGuide).inset(24)
      $0.width.equalTo(scroll.frameLayoutGuide).offset(-48)
    }

    // 等待 @Published 赋值完成再重建，保证文字和选中值来自同一次设置。
    observation = AppModel.shared.$preferences.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuild() }
  }

  /// 重新构建设置项，以容纳不同语言的文字长度和即时选中状态。
  private func rebuild() {
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

    let title = UILabel()
    title.text = Localization.text("settings")
    title.font = .preferredFont(forTextStyle: .largeTitle)
    title.adjustsFontForContentSizeCategory = true
    title.numberOfLines = 0

    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "xmark"), for: .normal)
    close.accessibilityLabel = Localization.text("close")
    close.accessibilityIdentifier = "close-settings"
    close.addTarget(self, action: #selector(done), for: .touchUpInside)
    close.snp.makeConstraints { $0.width.height.equalTo(44) }
    let header = UIStackView(arrangedSubviews: [title, close])
    header.alignment = .center
    header.spacing = 12
    stack.addArrangedSubview(header)

    addLabel("appearance")
    addOptions(
      [Localization.text("system"), Localization.text("light"), Localization.text("dark")],
      selected: AppModel.shared.preferences.appearance,
      action: #selector(theme(_:)))
    addLabel("language")
    addOptions(
      [Localization.text("system"), "简体中文", "繁體中文", "English"],
      selected: ["system", "zh-Hans", "zh-Hant", "en"].firstIndex(of: AppModel.shared.preferences.language) ?? 0,
      action: #selector(language(_:)))
    addLabel("version", suffix: " " + AppInfo.version)

    let feedback = UIButton(type: .system)
    feedback.setTitle(Localization.text("feedback"), for: .normal)
    feedback.titleLabel?.numberOfLines = 0
    feedback.addTarget(self, action: #selector(openFeedback), for: .touchUpInside)
    stack.addArrangedSubview(feedback)
    addLabel("privacy")
    addLabel("local")
  }

  /// 将选项竖排并允许标题换行，窄抽屉和大字体下不截断语言名称。
  private func addOptions(_ titles: [String], selected: Int, action: Selector) {
    let options = UIStackView()
    options.axis = .vertical
    options.spacing = 4
    for (index, title) in titles.enumerated() {
      let button = UIButton(type: .system)
      var configuration = UIButton.Configuration.plain()
      configuration.title = title
      configuration.image = UIImage(systemName: index == selected ? "checkmark.circle.fill" : "circle")
      configuration.imagePadding = 12
      configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
      configuration.background.backgroundColor = .secondarySystemGroupedBackground
      configuration.background.cornerRadius = 10
      button.configuration = configuration
      button.contentHorizontalAlignment = .leading
      button.titleLabel?.numberOfLines = 0
      button.titleLabel?.adjustsFontForContentSizeCategory = true
      button.tag = index
      if index == selected {
        button.accessibilityTraits.insert(.selected)
      }
      button.addTarget(self, action: action, for: .touchUpInside)
      options.addArrangedSubview(button)
    }
    stack.addArrangedSubview(options)
  }

  private func addLabel(_ key: String, suffix: String = "") {
    let label = UILabel()
    label.text = Localization.text(key) + suffix
    label.numberOfLines = 0
    label.font = .preferredFont(forTextStyle: .body)
    label.adjustsFontForContentSizeCategory = true
    stack.addArrangedSubview(label)
  }

  @objc private func done() {
    onClose?()
  }

  @objc private func theme(_ sender: UIButton) {
    var value = AppModel.shared.preferences
    value.appearance = sender.tag

    do {
      try AppModel.shared.setPreferences(value)
    } catch {
      showError(error)
    }
  }

  @objc private func language(_ sender: UIButton) {
    var value = AppModel.shared.preferences
    value.language = ["system", "zh-Hans", "zh-Hant", "en"][sender.tag]

    do {
      try AppModel.shared.setPreferences(value)
    } catch {
      showError(error)
    }
  }

  @objc private func openFeedback() {
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
