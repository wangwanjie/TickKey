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
    let picker = PerformanceDiagnostics.measure("import.picker.create") {
      UIDocumentPickerViewController(forOpeningContentTypes: [.data, .text], asCopy: true)
    }
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

    controller.dismiss(animated: true) { [weak self] in
      self?.work("import.file.read", { try Self.readImport(url) }, completion: { [weak self] result in
        guard let self else {
          return
        }
        do {
          let data = try result.get()
          if BackupCodec.isEncrypted(data) {
            password(exporting: false) { [weak self] in self?.decode(data, password: $0) }
          } else {
            decode(data, password: nil)
          }
        } catch {
          presenter?.showError(error)
        }
      })
    }
  }

  /// 后台限定最大读取量，文件大小缺失或读取期间变化时也不会无界分配内存。
  private nonisolated static func readImport(_ url: URL) throws -> Data {
    let access = url.startAccessingSecurityScopedResource()
    defer {
      if access {
        url.stopAccessingSecurityScopedResource()
      }
    }
    guard let stream = InputStream(url: url) else {
      throw TickKeyError.unsupportedFormat
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count >= 0 else {
        throw TickKeyError.unsupportedFormat
      }
      if count == 0 {
        break
      }
      guard data.count + count <= BackupCodec.maximumSize else {
        throw TickKeyError.unsupportedFormat
      }
      data.append(contentsOf: buffer.prefix(count))
    }
    return data
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let temporaryExport {
      try? FileManager.default.removeItem(at: temporaryExport.deletingLastPathComponent())
      self.temporaryExport = nil
    }
  }

  /// 解码与持久化均在后台进行，整个过程保留进度提示，完成后再反馈结果。
  private func decode(_ data: Data, password: String?) {
    process { finish in
      DispatchQueue.global(qos: .userInitiated).async {
        let result = Result {
          try PerformanceDiagnostics.measure("import.decode", count: data.count) {
            try BackupCodec.decode(data, password: password)
          }
        }
        DispatchQueue.main.async {
          switch result {
          case let .success(tokens):
            AppModel.shared.importTokens(tokens, completion: finish)
          case let .failure(error):
            finish(.failure(error))
          }
        }
      }
    } completion: { [weak self] (result: Result<String, Error>) in
      switch result {
      case let .success(message):
        self?.presenter?.showMessage(message)
      case let .failure(error):
        self?.presenter?.showError(error)
      }
    }
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
        self?.save(extension: "tickkey") { try BackupCodec.encrypt(tokens, password: password) }
      }
    })
    sheet.addAction(UIAlertAction(title: Localization.text("text.format"), style: .default) { [weak self] _ in
      self?.presenter?.confirm(
        title: Localization.text("text.format"),
        message: Localization.text("plaintext.warning")) {
          let tokens = AppModel.shared.tokens
          self?.save(extension: "txt") { try BackupCodec.text(tokens) }
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
  private func save(extension ext: String, data: @escaping () throws -> Data) {
    work(
      "export.prepare",
      {
        let content = try data()
        let folder = FileManager.default
          .temporaryDirectory
          .appendingPathComponent("TickKey-export-" + UUID().uuidString)
        do {
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let url = folder.appendingPathComponent("TickKey-backup." + ext)
          try content.write(to: url, options: [.atomic, .completeFileProtection])
          return url
        } catch {
          try? FileManager.default.removeItem(at: folder)
          throw error
        }
      }, completion: { [weak self] result in
        do {
          let url = try result.get()
          guard let self, let presenter else {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            return
          }
          temporaryExport = url
          let picker = PerformanceDiagnostics.measure("export.picker.create") {
            UIDocumentPickerViewController(forExporting: [url], asCopy: true)
          }
          picker.delegate = self
          presenter.present(picker, animated: true)
        } catch {
          self?.presenter?.showError(error)
        }
      })
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
    PerformanceDiagnostics.event("qr.open", count: tokens.count)
    guard !tokens.isEmpty else {
      return
    }
    presenter?.present(UINavigationController(rootViewController: QRViewController(tokens: tokens)), animated: true)
  }

  /// 将耗时的密码派生和文件解码移到后台，完成后再关闭进度提示并更新界面。
  private func work<T>(
    _ name: StaticString,
    _ operation: @escaping () throws -> T,
    completion: @escaping (Result<T, Error>) -> Void) {
    process({ finish in
      DispatchQueue.global(qos: .userInitiated).async {
        let result = Result { try PerformanceDiagnostics.measure(name, operation) }
        DispatchQueue.main.async { finish(result) }
      }
    }, completion: completion)
  }

  /// 统一进度生命周期，允许后台解码后继续异步持久化，而不提前关闭进度界面。
  private func process<T>(
    _ start: @escaping (@escaping (Result<T, Error>) -> Void) -> Void,
    completion: @escaping (Result<T, Error>) -> Void) {
    let alert = UIAlertController(title: Localization.text("processing"), message: nil, preferredStyle: .alert)
    PerformanceDiagnostics.event("transfer.progress.requested")
    presenter?.present(alert, animated: true) {
      PerformanceDiagnostics.event("transfer.progress.visible")
      start { result in
        alert.dismiss(animated: true) { completion(result) }
      }
    }
  }
}
