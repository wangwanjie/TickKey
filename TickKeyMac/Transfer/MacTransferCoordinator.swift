import AppKit
import UniformTypeIdentifiers

/// 管理 Mac 文件面板、密码交互和备份任务，避免在界面线程执行密码派生。
@MainActor
internal final class MacTransferCoordinator {
  private weak var presenter: NSViewController?
  private var qr: MacQRViewController?

  init(presenter: NSViewController) {
    self.presenter = presenter
  }

  /// 通过用户选择取得文件权限，检查大小并按内容识别加密或文本格式。
  func chooseImport() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else {
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
      var pass: String?

      if BackupCodec.isEncrypted(data) {
        guard let password = password(exporting: false) else {
          return
        }
        pass = password
      }
      work({ try BackupCodec.decode(data, password: pass) }, completion: { result in
        do {
          try MacAlerts.message(AppModel.shared.importTokens(result.get()))
        } catch {
          MacAlerts.error(error)
        }
      })
    } catch {
      MacAlerts.error(error)
    }
  }

  /// 固定导出全部账户，明文方式需确认，二维码方式交给分页控制器。
  func chooseExport() {
    let tokens = AppModel.shared.tokens

    guard !tokens.isEmpty else {
      MacAlerts.message(Localization.text("empty.body"))
      return
    }

    let alert = NSAlert()
    alert.messageText = Localization.text("export")
    alert.informativeText = Localization.text("export.scope")
    ["encrypted.format", "text.format", "qr.batch", "cancel"]
      .forEach { alert.addButton(withTitle: Localization.text($0)) }

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      guard let password = password(exporting: true) else {
        return
      }
      work({ try BackupCodec.encrypt(tokens, password: password) }, completion: { [weak self] result in
        do {
          try self?.save(result.get(), extension: "tickkey")
        } catch {
          MacAlerts.error(error)
        }
      })
    case .alertSecondButtonReturn:
      guard MacAlerts.confirm(Localization.text("plaintext.warning")) else {
        return
      }

      do {
        try save(BackupCodec.text(tokens), extension: "txt")
      } catch {
        MacAlerts.error(error)
      }
    case .alertThirdButtonReturn:
      showQR(tokens)
    default:
      break
    }
  }

  /// 只向保存面板选定的位置写入文件，并在完成后结束安全作用域访问。
  private func save(_ data: Data, extension ext: String) throws {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "TickKey-backup." + ext
    panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }

    let access = url.startAccessingSecurityScopedResource()
    defer {
      if access {
        url.stopAccessingSecurityScopedResource()
      }
    }
    try data.write(to: url, options: .atomic)
  }

  /// 使用安全输入框收集密码，导出时额外检查两次输入是否一致。
  private func password(exporting: Bool) -> String? {
    let alert = NSAlert()
    alert.messageText = Localization.text("password")
    alert.informativeText = exporting ? Localization.text("password.help") : ""

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = 12
    stack.frame = NSRect(x: 0, y: 0, width: 340, height: exporting ? 64 : 26)
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
    field.placeholderString = Localization.text("password")
    let confirm = NSSecureTextField(frame: field.frame)
    confirm.placeholderString = Localization.text("password.confirm")
    stack.addArrangedSubview(field)

    if exporting {
      stack.addArrangedSubview(confirm)
    }
    alert.accessoryView = stack
    alert.addButton(withTitle: Localization.text("continue"))
    alert.addButton(withTitle: Localization.text("cancel"))
    alert.window.initialFirstResponder = field

    guard alert.runModal() == .alertFirstButtonReturn else {
      return nil
    }

    if exporting, field.stringValue != confirm.stringValue {
      MacAlerts.message(Localization.text("password.mismatch"))

      return nil
    }

    return field.stringValue
  }

  func showQR(_ tokens: [Token]) {
    guard !tokens.isEmpty else {
      return
    }

    let qr = MacQRViewController(tokens: tokens)
    self.qr = qr
    presenter?.presentAsSheet(qr)
  }

  /// 处理任务期间阻止进度提示被提前关闭，后台完成后在主线程反馈结果。
  private func work<T>(_ operation: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
    let alert = NSAlert()
    alert.messageText = Localization.text("processing")
    alert.addButton(withTitle: Localization.text("processing")).isEnabled = false

    if let window = presenter?.view.window {
      alert.beginSheetModal(for: window)
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result { try operation() }
      DispatchQueue.main.async {
        if let parent = alert.window.sheetParent {
          parent.endSheet(alert.window)
        }
        alert.window.orderOut(nil)
        completion(result)
      }
    }
  }
}
