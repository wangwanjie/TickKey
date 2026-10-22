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

  /// 通过用户选择取得文件权限；可一次选择多份备份或二维码图片，按内容识别格式。
  func chooseImport() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.message = Localization.text("import.files.help")

    guard panel.runModal() == .OK, !panel.urls.isEmpty else {
      return
    }
    importFiles(panel.urls)
  }

  /// 打开面板和拖放共用：逐个读取文件，加密备份单独询问密码，全部识别后一次去重保存。
  func importFiles(_ urls: [URL]) {
    var sources: [(data: Data, password: String?)] = []

    do {
      for url in urls {
        let data = try Self.read(url)
        var passphrase: String?

        if BackupCodec.isEncrypted(data) {
          // 多个加密备份时在提示中带上文件名，避免把密码输错到另一份备份。
          guard let value = password(exporting: false, file: urls.count > 1 ? url.lastPathComponent : nil) else {
            return
          }
          passphrase = value
        }
        sources.append((data, passphrase))
      }
    } catch {
      MacAlerts.error(error)
      return
    }

    work({
      try sources.reduce(into: ImportDecoder.Result()) { total, source in
        let decoded = try ImportDecoder.decodeFile(source.data, password: source.password)
        total.tokens += decoded.tokens
        total.rejectedCodes += decoded.rejectedCodes
      }
    }, completion: { result in
      Self.finishImport(result)
    })
  }

  /// 读取剪贴板中的 otpauth 链接或二维码截图，识别在后台完成。
  func importFromClipboard() {
    let board = NSPasteboard.general
    let text = board.string(forType: .string)
    let image = NSImage(pasteboard: board).flatMap { image -> Data? in
      guard let tiff = image.tiffRepresentation else {
        return nil
      }
      return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
    work({ try ImportDecoder.decodePasteboard(text: text, image: image) }, completion: { result in
      Self.finishImport(result)
    })
  }

  /// 在安全作用域内读取用户选择或拖入的文件，并先按文件大小拒绝过大的内容。
  private static func read(_ url: URL) throws -> Data {
    let access = url.startAccessingSecurityScopedResource()
    defer {
      if access {
        url.stopAccessingSecurityScopedResource()
      }
    }

    guard try (url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= BackupCodec.maximumSize else {
      throw TickKeyError.unsupportedFormat
    }
    return try Data(contentsOf: url)
  }

  /// 统一保存识别结果并反馈新增、重复和跳过的数量。
  private static func finishImport(_ result: Result<ImportDecoder.Result, Error>) {
    do {
      let decoded = try result.get()
      var message = try AppModel.shared.importTokens(decoded.tokens)

      if decoded.rejectedCodes > 0 {
        message += "\n\n" + String(format: Localization.text("import.skipped.codes"), decoded.rejectedCodes)
      }
      MacAlerts.message(message)
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
    ["encrypted.format", "text.format", "qr.batch", "google.format", "cancel"]
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
    case let response where response.rawValue == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1:
      showGoogleQR(tokens)
    default:
      break
    }
  }

  /// 只向保存面板选定的位置写入文件，并在完成后结束安全作用域访问。
  private func save(_ data: Data, extension ext: String) throws {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = BackupCodec.fileName(extension: ext)
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
  private func password(exporting: Bool, file: String? = nil) -> String? {
    let alert = NSAlert()
    alert.messageText = Localization.text("password")
    alert.informativeText = exporting ? Localization.text("password.help") : (file ?? "")

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

  private func showGoogleQR(_ tokens: [Token]) {
    work({ try GoogleMigration.encode(tokens) }, completion: { [weak self] result in
      do {
        let qr = try MacQRViewController(migration: result.get())
        self?.qr = qr
        self?.presenter?.presentAsSheet(qr)
      } catch {
        MacAlerts.error(error)
      }
    })
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
