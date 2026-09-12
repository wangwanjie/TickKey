import UIKit
import UniformTypeIdentifiers

/// 协调文件选择、密码输入和备份处理，持久化统一经过共享模型。
@MainActor
internal final class IOSTransferCoordinator: NSObject, UIDocumentPickerDelegate {
  private weak var presenter: UIViewController?
  private var temporaryExport: URL?

  init(presenter: UIViewController) {
    self.presenter = presenter
  }

  func chooseImport() {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .text], asCopy: true)
    picker.delegate = self
    presenter?.present(picker, animated: true)
  }

  /// 在授权访问期间读取文件，等待文件面板关闭后再展示密码或处理状态。
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if let temporaryExport {
      try? FileManager.default.removeItem(at: temporaryExport.deletingLastPathComponent())
      self.temporaryExport = nil
      return
    }

    guard let url = urls.first else {
      return
    }

    do {
      let access = url.startAccessingSecurityScopedResource()
      defer {
        if access {
          url.stopAccessingSecurityScopedResource()
        }
      }

      guard try (url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= BackupCodec.maximumSize
      else {
        throw TickKeyError.unsupportedFormat
      }

      let data = try Data(contentsOf: url)
      controller.dismiss(animated: true) { [weak self] in
        guard let self else {
          return
        }

        if BackupCodec.isEncrypted(data) {
          password(exporting: false) { [weak self] in self?.decode(data, password: $0) }
        } else {
          decode(data, password: nil)
        }
      }
    } catch {
      controller.dismiss(animated: true) { [weak self] in
        self?.presenter?.showError(error)
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let temporaryExport {
      try? FileManager.default.removeItem(at: temporaryExport.deletingLastPathComponent())
      self.temporaryExport = nil
    }
  }

  /// 在后台解码完整文件，回到主线程后一次性导入并反馈去重结果。
  private func decode(_ data: Data, password: String?) {
    work({ try BackupCodec.decode(data, password: password) }, completion: { [weak self] result in
      guard let self else {
        return
      }

      do {
        let tokens = try result.get()
        let message = try AppModel.shared.importTokens(tokens)
        presenter?.showMessage(message)
      } catch {
        presenter?.showError(error)
      }
    })
  }

  /// 明确导出范围与格式，明文导出前提示文件包含账户密钥。
  func chooseExport(anchor: UIBarButtonItem?) {
    guard !AppModel.shared.tokens.isEmpty else {
      presenter?.showMessage(Localization.text("empty.body"))
      return
    }

    let sheet = UIAlertController(
      title: Localization.text("export"),
      message: Localization.text("export.scope"),
      preferredStyle: .actionSheet)
    sheet.addAction(UIAlertAction(title: Localization.text("encrypted.format"), style: .default) { [weak self] _ in
      self?.password(exporting: true) { [weak self] password in
        let tokens = AppModel.shared.tokens
        self?.work({ try BackupCodec.encrypt(tokens, password: password) }, completion: { result in
          do {
            try self?.save(result.get(), extension: "tickkey")
          } catch {
            self?.presenter?.showError(error)
          }
        })
      }
    })
    sheet.addAction(UIAlertAction(title: Localization.text("text.format"), style: .default) { [weak self] _ in
      self?.presenter?.confirm(
        title: Localization.text("text.format"),
        message: Localization.text("plaintext.warning")) {
          do {
            try self?.save(BackupCodec.text(AppModel.shared.tokens), extension: "txt")
          } catch {
            self?.presenter?.showError(error)
          }
        }
    })
    sheet
      .addAction(UIAlertAction(title: Localization.text("qr.batch"), style: .default) { [weak self] _ in
        self?.showQR(AppModel.shared.tokens)
      })
    sheet.addAction(UIAlertAction(title: Localization.text("cancel"), style: .cancel))
    sheet.popoverPresentationController?.barButtonItem = anchor
    presenter?.present(sheet, animated: true)
  }

  /// 先写入受文件保护的临时目录，再由系统文件面板导出到用户选定位置。
  private func save(_ data: Data, extension ext: String) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TickKey-export-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("TickKey-backup." + ext)
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    temporaryExport = url
    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    picker.delegate = self
    presenter?.present(picker, animated: true)
  }

  /// 导出时要求再次确认密码，导入时只收集解密所需的密码。
  private func password(exporting: Bool, completion: @escaping (String) -> Void) {
    let alert = UIAlertController(
      title: Localization.text("password"),
      message: exporting ? Localization.text("password.help") : nil,
      preferredStyle: .alert)
    alert.addTextField {
      $0.isSecureTextEntry = true
      $0.placeholder = Localization.text("password")
    }

    if exporting {
      alert.addTextField {
        $0.isSecureTextEntry = true
        $0.placeholder = Localization.text("password.confirm")
      }
    }
    alert.addAction(UIAlertAction(title: Localization.text("cancel"), style: .cancel))
    alert.addAction(UIAlertAction(title: Localization.text("continue"), style: .default) { [weak self, weak alert] _ in
      let password = alert?.textFields?.first?.text ?? ""

      if exporting,
         password != alert?.textFields?.last?.text {
        self?.presenter?.showMessage(Localization.text("password.mismatch"))
        return
      }
      completion(password)
    })
    presenter?.present(alert, animated: true)
  }

  func showQR(_ tokens: [Token]) {
    guard !tokens.isEmpty else {
      return
    }
    presenter?.present(UINavigationController(rootViewController: QRViewController(tokens: tokens)), animated: true)
  }

  /// 将耗时的密码派生和文件解码移到后台，完成后再关闭进度提示并更新界面。
  private func work<T>(_ operation: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
    let alert = UIAlertController(title: Localization.text("processing"), message: nil, preferredStyle: .alert)
    presenter?.present(alert, animated: true) {
      DispatchQueue.global(qos: .userInitiated).async {
        let result = Result { try operation() }
        DispatchQueue.main.async { alert.dismiss(animated: true) { completion(result) } }
      }
    }
  }
}
