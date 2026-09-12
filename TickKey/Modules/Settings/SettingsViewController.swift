import UIKit
import Combine
import SnapKit

final class SettingsViewController: UIViewController, UIViewControllerTransitioningDelegate {
    private let stack = UIStackView()
    private var observation: AnyCancellable?
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let scroll = UIScrollView(); view.addSubview(scroll); scroll.addSubview(stack)
        scroll.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        stack.axis = .vertical; stack.spacing = 24
        stack.snp.makeConstraints { $0.edges.equalTo(scroll.contentLayoutGuide).inset(24); $0.width.equalTo(scroll.frameLayoutGuide).offset(-48) }
        observation = AppModel.shared.$preferences.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuild() }
    }
    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let title = UILabel(); title.text = L.text("settings"); title.font = .preferredFont(forTextStyle: .largeTitle)
        let close = UIButton(type: .system); close.setTitle(L.text("close"), for: .normal); close.addTarget(self, action: #selector(done), for: .touchUpInside)
        stack.addArrangedSubview(title); stack.addArrangedSubview(close)
        let appearance = UISegmentedControl(items: [L.text("system"), L.text("light"), L.text("dark")])
        appearance.selectedSegmentIndex = AppModel.shared.preferences.appearance
        appearance.addTarget(self, action: #selector(theme(_:)), for: .valueChanged)
        addLabel("appearance"); stack.addArrangedSubview(appearance)
        let language = UISegmentedControl(items: [L.text("system"), "简体", "繁體", "EN"])
        language.selectedSegmentIndex = ["system", "zh-Hans", "zh-Hant", "en"].firstIndex(of: AppModel.shared.preferences.language) ?? 0
        language.addTarget(self, action: #selector(language(_:)), for: .valueChanged)
        addLabel("language"); stack.addArrangedSubview(language)
        addLabel("version", suffix: " " + AppInfo.version)
        let feedback = UIButton(type: .system); feedback.setTitle(L.text("feedback"), for: .normal)
        feedback.titleLabel?.numberOfLines = 0; feedback.addTarget(self, action: #selector(openFeedback), for: .touchUpInside)
        stack.addArrangedSubview(feedback); addLabel("privacy"); addLabel("local")
    }
    private func addLabel(_ key: String, suffix: String = "") {
        let label = UILabel(); label.text = L.text(key) + suffix; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body); label.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(label)
    }
    @objc private func done() { dismiss(animated: true) }
    @objc private func theme(_ sender: UISegmentedControl) {
        var value = AppModel.shared.preferences; value.appearance = sender.selectedSegmentIndex
        do { try AppModel.shared.setPreferences(value) } catch { showError(error) }
    }
    @objc private func language(_ sender: UISegmentedControl) {
        var value = AppModel.shared.preferences; value.language = ["system", "zh-Hans", "zh-Hant", "en"][sender.selectedSegmentIndex]
        do { try AppModel.shared.setPreferences(value) } catch { showError(error) }
    }
    @objc private func openFeedback() {
        guard let url = AppInfo.issuesURL else { showMessage(L.text("repo.unconfigured")); return }
        UIApplication.shared.open(url)
    }
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        DrawerPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

final class DrawerPresentationController: UIPresentationController {
    private let dimming = UIControl()
    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        return CGRect(x: 0, y: 0, width: min(containerView.bounds.width * 0.9, 440), height: containerView.bounds.height)
    }
    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        dimming.backgroundColor = UIColor.label.withAlphaComponent(0.2); dimming.frame = containerView.bounds
        dimming.addTarget(self, action: #selector(close), for: .touchUpInside)
        containerView.insertSubview(dimming, at: 0)
    }
    override func containerViewWillLayoutSubviews() { super.containerViewWillLayoutSubviews(); presentedView?.frame = frameOfPresentedViewInContainerView; dimming.frame = containerView?.bounds ?? .zero }
    override func dismissalTransitionDidEnd(_ completed: Bool) { if completed { dimming.removeFromSuperview() } }
    @objc private func close() { presentedViewController.dismiss(animated: true) }
}
