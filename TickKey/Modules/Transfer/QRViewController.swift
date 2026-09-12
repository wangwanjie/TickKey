import UIKit
import SnapKit

final class QRViewController: UIViewController {
    private let tokens: [Token]
    private var index = 0
    private let image = UIImageView(), account = UILabel(), counter = UILabel()
    private let previous = UIButton(type: .system), nextButton = UIButton(type: .system)
    init(tokens: [Token]) { self.tokens = tokens; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        title = L.text("qr.batch")
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: L.text("close"), style: .done, target: self, action: #selector(close))
        let scroll = UIScrollView(), stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 20; stack.alignment = .center
        view.addSubview(scroll); scroll.addSubview(stack)
        scroll.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        stack.snp.makeConstraints { $0.edges.equalTo(scroll.contentLayoutGuide).inset(24); $0.width.equalTo(scroll.frameLayoutGuide).offset(-48) }
        account.numberOfLines = 0; account.textAlignment = .center; account.font = .preferredFont(forTextStyle: .headline)
        image.contentMode = .scaleAspectFit; image.layer.magnificationFilter = .nearest
        image.snp.makeConstraints { $0.width.equalTo(stack).priority(750); $0.width.lessThanOrEqualTo(360); $0.height.equalTo(image.snp.width) }
        let warning = UILabel(); warning.text = L.text("qr.warning"); warning.numberOfLines = 0; warning.textColor = .secondaryLabel; warning.textAlignment = .center
        previous.setTitle(L.text("previous"), for: .normal); nextButton.setTitle(L.text("next"), for: .normal)
        previous.addTarget(self, action: #selector(back), for: .touchUpInside); nextButton.addTarget(self, action: #selector(forward), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [previous, counter, nextButton]); buttons.spacing = 24
        [account, image, buttons, warning].forEach(stack.addArrangedSubview)
        refresh()
    }
    private func refresh() {
        account.text = tokens[index].title + "\n" + tokens[index].account
        do { image.image = UIImage(cgImage: try QRCode.image(for: tokens[index])) } catch { showError(error) }
        counter.text = "\(index + 1) / \(tokens.count)"
        previous.isEnabled = index > 0; nextButton.isEnabled = index + 1 < tokens.count
    }
    @objc private func back() { index -= 1; refresh() }
    @objc private func forward() { index += 1; refresh() }
    @objc private func close() { dismiss(animated: true) }
}
