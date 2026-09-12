import UIKit
import SnapKit

final class CountdownView: UIView {
    var fraction: Double = 1 { didSet { setNeedsDisplay() } }
    override func draw(_ rect: CGRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 2
        let background = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        tintColor.withAlphaComponent(0.13).setFill(); background.fill()
        let path = UIBezierPath(); path.move(to: center)
        path.addArc(withCenter: center, radius: radius, startAngle: -.pi / 2,
                    endAngle: -.pi / 2 + .pi * 2 * fraction, clockwise: true)
        path.close(); tintColor.setFill(); path.fill()
    }
}

final class TokenCell: UICollectionViewCell {
    static let reuseID = "TokenCell"
    private let issuer = UILabel(), account = UILabel(), code = UILabel(), badge = UILabel()
    private let countdown = CountdownView()
    private let more = UIButton(type: .system)
    var onMore: (() -> Void)?
    var token: Token?
    private var lastStep: Int?
    private var lastCode = "—"
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 20; contentView.layer.borderWidth = 1
        badge.textAlignment = .center; badge.font = .systemFont(ofSize: 20, weight: .bold)
        badge.textColor = tintColor; badge.backgroundColor = tintColor.withAlphaComponent(0.1)
        badge.layer.cornerRadius = 12; badge.clipsToBounds = true
        issuer.font = .preferredFont(forTextStyle: .headline)
        account.font = .preferredFont(forTextStyle: .caption1); account.textColor = .secondaryLabel
        code.font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold); code.textColor = tintColor
        issuer.adjustsFontForContentSizeCategory = true; account.adjustsFontForContentSizeCategory = true
        more.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        more.addTarget(self, action: #selector(menu), for: .touchUpInside)
        countdown.backgroundColor = .clear
        [badge, issuer, account, code, countdown, more].forEach(contentView.addSubview)
        badge.snp.makeConstraints { $0.top.leading.equalToSuperview().inset(18); $0.size.equalTo(42) }
        more.snp.makeConstraints { $0.top.trailing.equalToSuperview().inset(8); $0.size.equalTo(44) }
        issuer.snp.makeConstraints { $0.leading.equalTo(badge.snp.trailing).offset(12); $0.top.equalTo(badge); $0.trailing.lessThanOrEqualTo(more.snp.leading) }
        account.snp.makeConstraints { $0.leading.trailing.equalTo(issuer); $0.top.equalTo(issuer.snp.bottom).offset(5) }
        code.snp.makeConstraints { $0.leading.equalTo(badge); $0.bottom.equalToSuperview().inset(18); $0.trailing.lessThanOrEqualTo(countdown.snp.leading).offset(-8) }
        countdown.snp.makeConstraints { $0.trailing.bottom.equalToSuperview().inset(20); $0.size.equalTo(26) }
        code.adjustsFontSizeToFitWidth = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func menu() { onMore?() }
    func configure(_ token: Token) {
        self.token = token
        lastStep = nil
        issuer.text = token.title; account.text = token.account; badge.text = String(token.title.prefix(1)).uppercased()
        more.accessibilityLabel = L.text("edit") + " " + token.account
        accessibilityIdentifier = "token-" + token.account
        tick()
    }
    func tick() {
        guard let token else { return }
        let step = Int(Date().timeIntervalSince1970 / Double(token.period))
        if step != lastStep {
            lastStep = step; lastCode = (try? TOTP.code(for: token)).map(TOTP.display) ?? "—"
        }
        code.text = lastCode
        countdown.fraction = TOTP.remainingFraction(for: token)
        countdown.accessibilityLabel = String(Int(ceil(countdown.fraction * Double(token.period)))) + " s"
        contentView.layer.borderColor = UIColor.separator.withAlphaComponent(0.25).cgColor
    }
}
