import AppKit
import SnapKit

final class MacTokenEditor: NSViewController {
    private let original: Token?
    private let issuer = NSTextField(), account = NSTextField(), secret = NSSecureTextField(), digits = NSTextField(), period = NSTextField()
    private let algorithm = NSPopUpButton()
    init(token: Token?) { original = token; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 560)) }
    override func viewDidLoad() {
        super.viewDidLoad()
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        view.addSubview(stack); stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(28) }
        let title = NSTextField(labelWithString: L.text(original == nil ? "add" : "edit")); title.font = .systemFont(ofSize: 22, weight: .bold); stack.addArrangedSubview(title)
        for (key, field) in [("issuer", issuer), ("account", account), ("secret", secret as NSTextField), ("digits", digits), ("period", period)] {
            stack.addArrangedSubview(NSTextField(labelWithString: L.text(key)))
            field.placeholderString = L.text(key); field.identifier = NSUserInterfaceItemIdentifier(key)
            stack.addArrangedSubview(field); field.snp.makeConstraints { $0.width.equalTo(stack) }
        }
        stack.addArrangedSubview(NSTextField(labelWithString: L.text("algorithm")))
        algorithm.addItems(withTitles: OTPAlgorithm.allCases.map(\.rawValue)); stack.addArrangedSubview(algorithm)
        issuer.stringValue = original?.issuer ?? ""; account.stringValue = original?.account ?? ""; secret.stringValue = original?.secret ?? ""
        digits.stringValue = String(original?.digits ?? 6); period.stringValue = String(original?.period ?? 30)
        algorithm.selectItem(withTitle: (original?.algorithm ?? .sha1).rawValue)
        let cancel = NSButton(title: L.text("cancel"), target: self, action: #selector(cancel)); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: L.text("save"), target: self, action: #selector(save)); save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        let actions = NSStackView(views: [cancel, save]); actions.spacing = 12; stack.addArrangedSubview(actions)
    }
    @objc private func cancel() { dismiss(self) }
    @objc private func save() {
        do {
            let token = try Token(id: original?.id ?? UUID(), issuer: issuer.stringValue, account: account.stringValue,
                                  secret: secret.stringValue, algorithm: OTPAlgorithm.allCases[algorithm.indexOfSelectedItem],
                                  digits: Int(digits.stringValue) ?? 0, period: Int(period.stringValue) ?? 0)
            if original == nil {
                if try AppModel.shared.add([token]).duplicates > 0 { throw TickKeyError.duplicate }
            } else { try AppModel.shared.update(token) }
            dismiss(self)
        } catch { MacAlerts.error(error) }
    }
}
