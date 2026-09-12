import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacTransferCoordinator {
    private weak var presenter: NSViewController?
    private var qr: MacQRViewController?
    init(presenter: NSViewController) { self.presenter = presenter }
    func chooseImport() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= BackupCodec.maximumSize else { throw TickKeyError.unsupportedFormat }
            let data = try Data(contentsOf: url)
            var pass: String?
            if BackupCodec.isEncrypted(data) { guard let password = password(exporting: false) else { return }; pass = password }
            work({ try BackupCodec.decode(data, password: pass) }) { result in
                do { MacAlerts.message(try AppModel.shared.importTokens(result.get())) } catch { MacAlerts.error(error) }
            }
        } catch { MacAlerts.error(error) }
    }
    func chooseExport() {
        let tokens = AppModel.shared.tokens
        guard !tokens.isEmpty else { MacAlerts.message(L.text("empty.body")); return }
        let alert = NSAlert(); alert.messageText = L.text("export"); alert.informativeText = L.text("export.scope")
        ["encrypted.format", "text.format", "qr.batch", "cancel"].forEach { alert.addButton(withTitle: L.text($0)) }
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard let password = password(exporting: true) else { return }
            work({ try BackupCodec.encrypt(tokens, password: password) }) { [weak self] result in
                do { try self?.save(result.get(), extension: "tickkey") } catch { MacAlerts.error(error) }
            }
        case .alertSecondButtonReturn:
            guard MacAlerts.confirm(L.text("plaintext.warning")) else { return }
            do { try save(BackupCodec.text(tokens), extension: "txt") } catch { MacAlerts.error(error) }
        case .alertThirdButtonReturn: showQR(tokens)
        default: break
        }
    }
    private func save(_ data: Data, extension ext: String) throws {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "TickKey-backup." + ext
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try data.write(to: url, options: .atomic)
    }
    private func password(exporting: Bool) -> String? {
        let alert = NSAlert(); alert.messageText = L.text("password"); alert.informativeText = exporting ? L.text("password.help") : ""
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 12; stack.frame = NSRect(x: 0, y: 0, width: 340, height: exporting ? 64 : 26)
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24)); field.placeholderString = L.text("password")
        let confirm = NSSecureTextField(frame: field.frame); confirm.placeholderString = L.text("password.confirm")
        stack.addArrangedSubview(field); if exporting { stack.addArrangedSubview(confirm) }
        alert.accessoryView = stack; alert.addButton(withTitle: L.text("continue")); alert.addButton(withTitle: L.text("cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        if exporting && field.stringValue != confirm.stringValue { MacAlerts.message(L.text("password.mismatch")); return nil }
        return field.stringValue
    }
    func showQR(_ tokens: [Token]) {
        guard !tokens.isEmpty else { return }
        let qr = MacQRViewController(tokens: tokens); self.qr = qr; presenter?.presentAsSheet(qr)
    }
    private func work<T>(_ operation: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        let alert = NSAlert(); alert.messageText = L.text("processing")
        alert.addButton(withTitle: L.text("processing")).isEnabled = false
        if let window = presenter?.view.window { alert.beginSheetModal(for: window) }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                if let parent = alert.window.sheetParent { parent.endSheet(alert.window) }
                alert.window.orderOut(nil); completion(result)
            }
        }
    }
}
