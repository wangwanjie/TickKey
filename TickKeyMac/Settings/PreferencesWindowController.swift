import AppKit
import Combine
import SnapKit

final class PreferencesWindowController: NSWindowController {
    private let tabs = NSSegmentedControl(), scroll = NSScrollView(), stack = NSStackView()
    private var observation: AnyCancellable?
    private let content = NSView()
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window); window.isReleasedWhenClosed = false; window.center(); window.contentView = content
        tabs.segmentCount = 3; tabs.selectedSegment = 0; tabs.target = self; tabs.action = #selector(tabChanged)
        content.addSubview(tabs); content.addSubview(scroll)
        tabs.snp.makeConstraints { $0.top.equalToSuperview().offset(20); $0.centerX.equalToSuperview() }
        scroll.snp.makeConstraints { $0.top.equalTo(tabs.snp.bottom).offset(24); $0.leading.trailing.bottom.equalToSuperview().inset(24) }
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 20
        let document = NSView(); scroll.documentView = document; document.addSubview(stack)
        document.snp.makeConstraints { $0.width.equalTo(scroll.contentView); $0.height.greaterThanOrEqualTo(230) }
        stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(8) }
        observation = AppModel.shared.$preferences.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuild() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tabChanged() { rebuild(); resize(animated: true) }
    private func resize(animated: Bool) {
        guard let window else { return }
        let height: CGFloat = [360, 310, 340][tabs.selectedSegment]
        let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 500, height: height))
        var frame = window.frame; frame.origin.y += frame.height - target.height; frame.size = target.size
        window.setFrame(frame, display: true, animate: animated)
    }
    private func label(_ value: String) {
        let field = NSTextField(wrappingLabelWithString: value); field.isSelectable = true
        stack.addArrangedSubview(field); field.snp.makeConstraints { $0.width.equalTo(stack) }
    }
    private func rebuild() {
        window?.title = L.text("settings")
        ["appearance", "updates", "about"].enumerated().forEach { tabs.setLabel(L.text($0.element), forSegment: $0.offset) }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch tabs.selectedSegment {
        case 0:
            label(L.text("appearance"))
            let theme = NSPopUpButton(); theme.addItems(withTitles: [L.text("system"), L.text("light"), L.text("dark")])
            theme.selectItem(at: AppModel.shared.preferences.appearance); theme.target = self; theme.action = #selector(themeChanged(_:)); stack.addArrangedSubview(theme)
            label(L.text("language"))
            let language = NSPopUpButton(); language.addItems(withTitles: [L.text("system"), "简体中文", "繁體中文", "English"])
            language.selectItem(at: ["system", "zh-Hans", "zh-Hant", "en"].firstIndex(of: AppModel.shared.preferences.language) ?? 0)
            language.target = self; language.action = #selector(languageChanged(_:)); stack.addArrangedSubview(language)
        case 1:
            label(L.text("version") + " " + AppInfo.version)
            let check = NSButton(title: L.text("check.updates"), target: UpdateController.shared, action: #selector(UpdateController.check)); check.bezelStyle = .rounded
            stack.addArrangedSubview(check)
            if !UpdateController.shared.configured { label(L.text("updates.unconfigured")) }
        default:
            label("TickKey " + AppInfo.version); label(L.text("privacy")); label(L.text("local"))
            let feedback = NSButton(title: L.text("feedback"), target: self, action: #selector(feedback)); feedback.bezelStyle = .rounded; stack.addArrangedSubview(feedback)
        }
    }
    @objc private func themeChanged(_ sender: NSPopUpButton) {
        var value = AppModel.shared.preferences; value.appearance = sender.indexOfSelectedItem
        do { try AppModel.shared.setPreferences(value) } catch { MacAlerts.error(error) }
    }
    @objc private func languageChanged(_ sender: NSPopUpButton) {
        var value = AppModel.shared.preferences; value.language = ["system", "zh-Hans", "zh-Hant", "en"][sender.indexOfSelectedItem]
        do { try AppModel.shared.setPreferences(value) } catch { MacAlerts.error(error) }
    }
    @objc private func feedback() { if let url = AppInfo.issuesURL { NSWorkspace.shared.open(url) } else { MacAlerts.message(L.text("repo.unconfigured")) } }
}
