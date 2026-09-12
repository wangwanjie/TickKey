import AppKit
import Combine
import SnapKit

final class MacAccountsViewController: NSViewController, NSSearchFieldDelegate {
    private let sidebar = NSView(), header = NSView(), scroll = NSScrollView(), canvas = NSView()
    private let search = NSSearchField(), heading = NSTextField(labelWithString: ""), summary = NSTextField(labelWithString: "")
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var cards: [MacTokenCard] = []
    private var subscriptions = Set<AnyCancellable>()
    private var sidebarLabels: [(NSTextField, String)] = []
    private var buttons: [(NSButton, String)] = []
    private lazy var transfer = MacTransferCoordinator(presenter: self)
    private var editor: MacTokenEditor?
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 1040, height: 720)) }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true; sidebar.wantsLayer = true
        [sidebar, header, scroll].forEach(view.addSubview)
        sidebar.snp.makeConstraints { $0.leading.top.bottom.equalToSuperview(); $0.width.equalTo(210) }
        header.snp.makeConstraints { $0.leading.equalTo(sidebar.snp.trailing); $0.top.trailing.equalToSuperview(); $0.height.equalTo(140) }
        scroll.snp.makeConstraints { $0.leading.equalTo(sidebar.snp.trailing); $0.top.equalTo(header.snp.bottom); $0.trailing.bottom.equalToSuperview() }
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.documentView = canvas
        let brand = NSTextField(labelWithString: "◈  TickKey"); brand.font = .systemFont(ofSize: 25, weight: .bold)
        sidebar.addSubview(brand); brand.snp.makeConstraints { $0.top.equalToSuperview().offset(34); $0.leading.equalToSuperview().offset(24) }
        let local = NSTextField(wrappingLabelWithString: ""); local.font = .systemFont(ofSize: 12); local.textColor = .secondaryLabelColor
        sidebar.addSubview(local); local.snp.makeConstraints { $0.top.equalTo(brand.snp.bottom).offset(12); $0.leading.trailing.equalToSuperview().inset(24) }
        sidebarLabels.append((local, "local"))
        let all = NSTextField(labelWithString: ""); all.font = .systemFont(ofSize: 14, weight: .semibold)
        sidebar.addSubview(all); all.snp.makeConstraints { $0.top.equalTo(local.snp.bottom).offset(44); $0.leading.trailing.equalToSuperview().inset(24) }
        sidebarLabels.append((all, "all.accounts"))
        let privacy = NSTextField(wrappingLabelWithString: ""); privacy.font = .systemFont(ofSize: 12); privacy.textColor = .secondaryLabelColor
        sidebar.addSubview(privacy); privacy.snp.makeConstraints { $0.leading.trailing.equalToSuperview().inset(24); $0.bottom.equalToSuperview().inset(28) }
        sidebarLabels.append((privacy, "privacy"))
        let settings = NSButton(title: "", target: self, action: #selector(showSettings)); settings.bezelStyle = .rounded
        sidebar.addSubview(settings); settings.snp.makeConstraints { $0.leading.equalToSuperview().offset(24); $0.bottom.equalTo(privacy.snp.top).offset(-24) }; buttons.append((settings, "settings"))
        heading.font = .systemFont(ofSize: 26, weight: .bold)
        summary.font = .systemFont(ofSize: 12); summary.textColor = .secondaryLabelColor
        [heading, summary, search].forEach(header.addSubview)
        heading.snp.makeConstraints { $0.top.equalToSuperview().offset(26); $0.leading.equalToSuperview().offset(28) }
        summary.snp.makeConstraints { $0.top.equalTo(heading.snp.bottom).offset(8); $0.leading.equalTo(heading) }
        search.delegate = self; search.sendsSearchStringImmediately = true
        search.snp.makeConstraints { $0.leading.equalTo(heading); $0.trailing.equalToSuperview().inset(28); $0.bottom.equalToSuperview().inset(12); $0.height.equalTo(28) }
        let actions = NSStackView(); actions.spacing = 8
        for (key, selector) in [("import", #selector(importAccounts)), ("export", #selector(exportAccounts)), ("add", #selector(addAccount))] {
            let button = NSButton(title: "", target: self, action: selector); button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier(key); actions.addArrangedSubview(button); buttons.append((button, key))
        }
        header.addSubview(actions); actions.snp.makeConstraints { $0.trailing.equalToSuperview().inset(28); $0.centerY.equalTo(heading) }
        heading.snp.makeConstraints { $0.trailing.lessThanOrEqualTo(actions.snp.leading).offset(-12) }
        empty.alignment = .center; empty.font = .systemFont(ofSize: 18); empty.textColor = .secondaryLabelColor
        canvas.addSubview(empty)
        AppModel.shared.$tokens.sink { [weak self] _ in DispatchQueue.main.async { self?.reload() } }.store(in: &subscriptions)
        AppModel.shared.$preferences.sink { [weak self] _ in self?.localize() }.store(in: &subscriptions)
        Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, self.view.window?.isVisible == true else { return }
            self.cards.filter { $0.frame.intersects(self.canvas.visibleRect) }.forEach { $0.tick(hidden: !NSApp.isActive) }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification).sink { [weak self] _ in self?.cards.forEach { $0.tick(hidden: true) } }.store(in: &subscriptions)
        reload()
    }
    override func viewDidAppear() { super.viewDidAppear(); if let error = AppModel.shared.startupError { MacAlerts.error(error) } }
    override func viewDidLayout() { super.viewDidLayout(); arrangeCards(); colors() }
    private func colors() { view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor }
    func controlTextDidChange(_ obj: Notification) { reload() }
    private func localize() {
        heading.stringValue = L.text("accounts"); summary.stringValue = L.text("subtitle")
        search.placeholderString = L.text("search")
        sidebarLabels.forEach { $0.0.stringValue = L.text($0.1) }; buttons.forEach { $0.0.title = L.text($0.1) }
        reload()
    }
    private func reload() {
        cards.forEach { $0.removeFromSuperview() }
        cards = AppModel.shared.tokens.filter { $0.matches(search.stringValue) }.map { token in
            let card = MacTokenCard(token: token)
            card.onEdit = { [weak self] in self?.edit(token) }
            card.onQR = { [weak self] in self?.transfer.showQR([token]) }
            card.onDelete = {
                if MacAlerts.confirm(L.text("delete.warning")) { do { try AppModel.shared.delete(token) } catch { MacAlerts.error(error) } }
            }
            canvas.addSubview(card); return card
        }
        empty.stringValue = L.text(AppModel.shared.tokens.isEmpty ? "empty.title" : "empty.search") + "\n\n" + L.text("empty.body")
        empty.isHidden = !cards.isEmpty
        arrangeCards()
    }
    private func arrangeCards() {
        let width = scroll.contentSize.width
        let columns = max(1, Int((width - 40 + 16) / 310))
        let cardWidth = floor((width - 48 - CGFloat(columns - 1) * 16) / CGFloat(columns))
        let rows = Int(ceil(Double(cards.count) / Double(columns)))
        let height = max(scroll.contentSize.height, CGFloat(rows) * 176 + 24)
        canvas.frame = NSRect(x: 0, y: 0, width: width, height: height)
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: 24 + CGFloat(index % columns) * (cardWidth + 16), y: height - 16 - CGFloat(index / columns + 1) * 176 + 16, width: cardWidth, height: 160)
        }
        empty.frame = NSRect(x: 30, y: max(20, height / 2 - 70), width: max(100, width - 60), height: 160)
    }
    @objc func addAccount() { edit(nil) }
    @objc func importAccounts() { transfer.chooseImport() }
    @objc func exportAccounts() { transfer.chooseExport() }
    @objc private func showSettings() { (NSApp.delegate as? MacAppDelegate)?.showPreferences() }
    private func edit(_ token: Token?) {
        let editor = MacTokenEditor(token: token); self.editor = editor
        presentAsSheet(editor)
    }
}

final class MacTokenCard: NSView {
    let token: Token
    var onEdit: (() -> Void)?, onQR: (() -> Void)?, onDelete: (() -> Void)?
    private let code = NSTextField(labelWithString: ""), issuer = NSTextField(labelWithString: ""), account = NSTextField(labelWithString: "")
    private let pie = MacCountdownView()
    private let more = NSButton()
    private var copiedUntil = Date.distantPast
    private var lastStep: Int?
    private var lastCode = "—"
    init(token: Token) {
        self.token = token; super.init(frame: .zero); wantsLayer = true; layer?.cornerRadius = 18; layer?.borderWidth = 1
        issuer.stringValue = token.title; issuer.font = .systemFont(ofSize: 15, weight: .semibold)
        account.stringValue = token.account; account.font = .systemFont(ofSize: 12); account.textColor = .secondaryLabelColor
        code.font = .monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
        [issuer, account, code, pie, more].forEach(addSubview)
        issuer.lineBreakMode = .byTruncatingTail; account.lineBreakMode = .byTruncatingMiddle
        more.title = "•••"; more.bezelStyle = .inline; more.target = self; more.action = #selector(showMenu)
        more.setAccessibilityLabel(L.text("edit") + " " + token.account)
        issuer.snp.makeConstraints { $0.leading.top.equalToSuperview().inset(20); $0.trailing.lessThanOrEqualTo(more.snp.leading).offset(-6) }
        account.snp.makeConstraints { $0.leading.trailing.equalTo(issuer); $0.top.equalTo(issuer.snp.bottom).offset(6) }
        more.snp.makeConstraints { $0.trailing.top.equalToSuperview().inset(12); $0.width.equalTo(32) }
        code.snp.makeConstraints { $0.leading.equalTo(issuer); $0.bottom.equalToSuperview().inset(20); $0.trailing.lessThanOrEqualTo(pie.snp.leading).offset(-8) }
        pie.snp.makeConstraints { $0.trailing.bottom.equalToSuperview().inset(22); $0.size.equalTo(26) }
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(token.title + ", " + token.account + ", " + L.text("copy"))
        tick(hidden: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func accessibilityPerformPress() -> Bool { copyCode(); return true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); copyCode() }
    override func keyDown(with event: NSEvent) { if event.characters == " " || event.keyCode == 36 { copyCode() } else { super.keyDown(with: event) } }
    @objc func copy(_ sender: Any?) { copyCode() }
    private func copyCode() {
        do {
            let value = try TOTP.code(for: token)
            let board = NSPasteboard.general; board.clearContents(); board.setString(value, forType: .string)
            let change = board.changeCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { if board.changeCount == change { board.clearContents() } }
            copiedUntil = Date().addingTimeInterval(2); tick(hidden: false)
        } catch { MacAlerts.error(error) }
    }
    func tick(hidden: Bool) {
        let step = Int(Date().timeIntervalSince1970 / Double(token.period))
        if !hidden && lastStep != step {
            lastStep = step; lastCode = (try? TOTP.code(for: token)).map(TOTP.display) ?? "—"
        }
        code.stringValue = hidden ? "••• •••" : lastCode
        account.stringValue = Date() < copiedUntil ? L.text("copied") : token.account
        pie.fraction = TOTP.remainingFraction(for: token)
        let accent = NSColor(named: "AccentColor") ?? .controlAccentColor
        code.textColor = accent; layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor; layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    }
    @objc private func showMenu() {
        let menu = NSMenu()
        for (key, action) in [("edit", #selector(edit)), ("qr", #selector(qr)), ("delete", #selector(deleteToken))] {
            let item = NSMenuItem(title: L.text(key), action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: more.frame.minX, y: more.frame.minY), in: self)
    }
    @objc private func edit() { onEdit?() }
    @objc private func qr() { onQR?() }
    @objc private func deleteToken() { onDelete?() }
}

final class MacCountdownView: NSView {
    var fraction: Double = 1 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor(named: "AccentColor") ?? .controlAccentColor
        accent.withAlphaComponent(0.13).setFill(); NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        let path = NSBezierPath(); let center = NSPoint(x: bounds.midX, y: bounds.midY)
        path.move(to: center); path.appendArc(withCenter: center, radius: bounds.width / 2 - 1, startAngle: 90, endAngle: 90 - CGFloat(fraction) * 360, clockwise: true)
        path.close(); accent.setFill(); path.fill()
    }
}
