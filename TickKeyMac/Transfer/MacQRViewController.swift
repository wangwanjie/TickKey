import AppKit
import SnapKit

final class MacQRViewController: NSViewController {
    private let tokens: [Token]
    private var index = 0
    private let image = NSImageView(), account = NSTextField(wrappingLabelWithString: ""), counter = NSTextField(labelWithString: "")
    private let previous = NSButton(), next = NSButton()
    init(tokens: [Token]) { self.tokens = tokens; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 600)) }
    override func viewDidLoad() {
        super.viewDidLoad()
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 20; stack.alignment = .centerX
        view.addSubview(stack); stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(24) }
        account.font = .systemFont(ofSize: 16, weight: .semibold); account.alignment = .center
        image.imageScaling = .scaleProportionallyUpOrDown; image.wantsLayer = true; image.layer?.magnificationFilter = .nearest
        image.snp.makeConstraints { $0.size.equalTo(340) }
        previous.title = L.text("previous"); previous.target = self; previous.action = #selector(back); previous.bezelStyle = .rounded
        next.title = L.text("next"); next.target = self; next.action = #selector(forward); next.bezelStyle = .rounded
        let buttons = NSStackView(views: [previous, counter, next]); buttons.spacing = 20
        let warning = NSTextField(wrappingLabelWithString: L.text("qr.warning")); warning.alignment = .center; warning.textColor = .secondaryLabelColor
        let close = NSButton(title: L.text("close"), target: self, action: #selector(close)); close.bezelStyle = .rounded; close.keyEquivalent = "\u{1b}"
        [account, image, buttons, warning, close].forEach(stack.addArrangedSubview)
        account.snp.makeConstraints { $0.width.equalTo(stack) }; warning.snp.makeConstraints { $0.width.equalTo(stack) }
        refresh()
    }
    private func refresh() {
        let token = tokens[index]; account.stringValue = token.title + "\n" + token.account
        do { image.image = NSImage(cgImage: try QRCode.image(for: token), size: .zero) } catch { MacAlerts.error(error) }
        counter.stringValue = "\(index + 1) / \(tokens.count)"; previous.isEnabled = index > 0; next.isEnabled = index + 1 < tokens.count
    }
    @objc private func back() { index -= 1; refresh() }
    @objc private func forward() { index += 1; refresh() }
    @objc private func close() { dismiss(self) }
}
