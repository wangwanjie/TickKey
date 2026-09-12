import UIKit
import UniformTypeIdentifiers

@MainActor
final class IOSTransferCoordinator: NSObject, UIDocumentPickerDelegate {
    private weak var presenter: UIViewController?
    private var temporaryExport: URL?
    init(presenter: UIViewController) { self.presenter = presenter }
    func chooseImport() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .text], asCopy: true)
        picker.delegate = self; presenter?.present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let temporaryExport { try? FileManager.default.removeItem(at: temporaryExport.deletingLastPathComponent()); self.temporaryExport = nil; return }
        guard let url = urls.first else { return }
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= BackupCodec.maximumSize else { throw TickKeyError.unsupportedFormat }
            let data = try Data(contentsOf: url)
            controller.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                if BackupCodec.isEncrypted(data) { self.password(exporting: false) { [weak self] in self?.decode(data, password: $0) } }
                else { self.decode(data, password: nil) }
            }
        } catch { controller.dismiss(animated: true) { [weak self] in self?.presenter?.showError(error) } }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if let temporaryExport { try? FileManager.default.removeItem(at: temporaryExport.deletingLastPathComponent()); self.temporaryExport = nil }
    }
    private func decode(_ data: Data, password: String?) {
        work({ try BackupCodec.decode(data, password: password) }) { [weak self] result in
            guard let self else { return }
            do { self.presenter?.showMessage(try AppModel.shared.importTokens(result.get())) }
            catch { self.presenter?.showError(error) }
        }
    }
    func chooseExport(anchor: UIBarButtonItem?) {
        guard !AppModel.shared.tokens.isEmpty else { presenter?.showMessage(L.text("empty.body")); return }
        let sheet = UIAlertController(title: L.text("export"), message: L.text("export.scope"), preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L.text("encrypted.format"), style: .default) { [weak self] _ in
            self?.password(exporting: true) { [weak self] password in
                let tokens = AppModel.shared.tokens
                self?.work({ try BackupCodec.encrypt(tokens, password: password) }) { result in
                    do { try self?.save(result.get(), extension: "tickkey") } catch { self?.presenter?.showError(error) }
                }
            }
        })
        sheet.addAction(UIAlertAction(title: L.text("text.format"), style: .default) { [weak self] _ in
            self?.presenter?.confirm(title: L.text("text.format"), message: L.text("plaintext.warning")) {
                do { try self?.save(BackupCodec.text(AppModel.shared.tokens), extension: "txt") } catch { self?.presenter?.showError(error) }
            }
        })
        sheet.addAction(UIAlertAction(title: L.text("qr.batch"), style: .default) { [weak self] _ in self?.showQR(AppModel.shared.tokens) })
        sheet.addAction(UIAlertAction(title: L.text("cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = anchor
        presenter?.present(sheet, animated: true)
    }
    private func save(_ data: Data, extension ext: String) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TickKey-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("TickKey-backup." + ext)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        temporaryExport = url
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = self; presenter?.present(picker, animated: true)
    }
    private func password(exporting: Bool, completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: L.text("password"), message: exporting ? L.text("password.help") : nil, preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = L.text("password") }
        if exporting { alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = L.text("password.confirm") } }
        alert.addAction(UIAlertAction(title: L.text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L.text("continue"), style: .default) { [weak self, weak alert] _ in
            let password = alert?.textFields?.first?.text ?? ""
            if exporting && password != alert?.textFields?.last?.text { self?.presenter?.showMessage(L.text("password.mismatch")); return }
            completion(password)
        })
        presenter?.present(alert, animated: true)
    }
    func showQR(_ tokens: [Token]) {
        guard !tokens.isEmpty else { return }
        presenter?.present(UINavigationController(rootViewController: QRViewController(tokens: tokens)), animated: true)
    }
    private func work<T>(_ operation: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        let alert = UIAlertController(title: L.text("processing"), message: nil, preferredStyle: .alert)
        presenter?.present(alert, animated: true) {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try operation() }
                DispatchQueue.main.async { alert.dismiss(animated: true) { completion(result) } }
            }
        }
    }
}
