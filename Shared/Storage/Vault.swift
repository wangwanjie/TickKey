import Combine
import CryptoKit
import Foundation
import GRDB
import MMKV
import Security

// MARK: - Vault

/// Keychain 中保存设备密钥，SQLite 只存认证加密后的完整账户记录。
/// 跨队列只共享不可变密钥、由 GRDB 串行化的 DatabaseQueue 和内部加锁的 MMKV；编解码器逐次创建。
internal final class Vault: @unchecked Sendable {
  /// 用于事务写入的密文记录，排序信息与账户内容分离。
  private struct EncryptedRecord {
    let id: String
    let payload: Data
    let position: Int
  }

  private let db: DatabaseQueue
  private let key: SymmetricKey
  private let settings: MMKV

  /// 打开本机保险库；已有数据库缺少设备密钥时拒绝创建新密钥，防止覆盖后无法恢复。
  init(directory: URL? = nil, testKey: Data? = nil) throws {
    let root = try directory ?? FileManager.default
      .url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true)
      .appendingPathComponent(
        "TickKey",
        isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // MMKV 仅保存外观和语言；账户内容使用下面的加密数据库。
    MMKV.initialize(rootDir: root.appendingPathComponent("settings").path)

    guard let settings = MMKV(mmapID: "preferences", rootPath: root.appendingPathComponent("settings").path)
    else {
      throw TickKeyError.storage
    }
    self.settings = settings

    // 设备密钥不迁移，数据库也排除系统备份，跨设备恢复应使用加密导出。
    var excluded = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try excluded.setResourceValues(values)

    // 已有数据库缺失 Keychain 密钥属于读取失败，不能生成新密钥覆盖。
    let databaseURL = root.appendingPathComponent("vault.sqlite")
    key = try testKey.map { SymmetricKey(data: $0) } ?? Self
      .deviceKey(allowCreate: !FileManager.default.fileExists(atPath: databaseURL.path))
    db = try DatabaseQueue(path: databaseURL.path)

    // 数据结构变更集中登记迁移，避免启动时隐式重建用户数据。
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
      try db.create(table: "tokens") { table in
        table.column("id", .text).primaryKey()
        table.column("payload", .blob).notNull()
        table.column("position", .integer).notNull()
      }
    }
    try migrator.migrate(db)
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: databaseURL.path)
    #endif
  }

  /// 按保存顺序解密账户，并核对密文绑定的 UUID，发现损坏时停止加载。
  func load() throws -> [Token] {
    try db.read { db in
      try Row.fetchAll(db, sql: "SELECT id, payload FROM tokens ORDER BY position").map { row in
        let id: String = row["id"]
        let payload: Data = row["payload"]
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: key, authenticating: Data(id.utf8))
        let token = try JSONDecoder().decode(Token.self, from: plain)
        try token.validate()

        guard token.id.uuidString == id else {
          throw TickKeyError.storage
        }

        return token
      }
    }
  }

  /// 先验证并加密所有账户，再以单个数据库事务替换记录，避免部分写入。
  func save(_ tokens: [Token]) throws {
    let records = try tokens.enumerated().map { index, token in
      try token.validate()
      let id = token.id.uuidString
      let sealed = try AES.GCM.seal(JSONEncoder().encode(token), using: key, authenticating: Data(id.utf8))

      guard let payload = sealed.combined else {
        throw TickKeyError.storage
      }

      return EncryptedRecord(id: id, payload: payload, position: index)
    }

    // 先完成全部加密，再进入事务；任一步失败都保留原有完整记录。
    try db.write { db in
      try db.execute(sql: "DELETE FROM tokens")

      for record in records {
        try db.execute(
          sql: "INSERT INTO tokens (id, payload, position) VALUES (?, ?, ?)",
          arguments: [record.id, record.payload, record.position])
      }
    }
  }

  /// 读取非敏感偏好设置，遇到过期或非法选项时回退到跟随系统。
  func preferences() throws -> Preferences {
    let language = settings.string(forKey: "language") ?? "system"
    let appearance = Int(settings.int32(forKey: "appearance"))

    return Preferences(
      language: ["system", "en", "zh-Hans", "zh-Hant"].contains(language) ? language : "system",
      appearance: (0 ... 2).contains(appearance) ? appearance : 0)
  }

  /// 轻量偏好写入 MMKV，写入失败时由界面显示错误。
  func savePreferences(_ value: Preferences) throws {
    guard settings.set(value.language, forKey: "language"),
          settings.set(Int32(value.appearance), forKey: "appearance") else {
      throw TickKeyError.storage
    }
  }

  /// 从 Keychain 读取设备密钥，仅首次创建保险库时允许生成新密钥。
  private static func deviceKey(allowCreate: Bool) throws -> SymmetricKey {
    let service = (Bundle.main.bundleIdentifier ?? "cn.vanjay.TickKey") + ".vault"
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "device-key-v1"
    ]
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)

    if status == errSecSuccess, let data = result as? Data, data.count == 32 {
      return SymmetricKey(data: data)
    }

    guard status == errSecItemNotFound, allowCreate else {
      throw TickKeyError.storage
    }

    let data = try BackupCodec.randomBytes(count: 32)
    var insert = query
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
      throw TickKeyError.storage
    }

    return SymmetricKey(data: data)
  }
}

// MARK: - Preferences

/// 两端共用的语言与外观设置，不包含账户或密钥。
internal struct Preferences {
  var language = "system"
  var appearance = 0
}

// MARK: - AppModel

/// 在主线程串行管理账户状态，持久化成功后再通知界面刷新。
@MainActor
internal final class AppModel: ObservableObject {
  static let shared = AppModel()
  @Published private(set) var tokens: [Token] = []
  @Published private(set) var preferences = Preferences()
  @Published private(set) var startupError: Error?
  private var vault: Vault?
  private let importQueue = DispatchQueue(label: "cn.vanjay.TickKey.import", qos: .userInitiated)
  private var importing = false

  /// 注入独立存储用于测试，避免回归测试触碰真实用户的保险库。
  init(vault: Vault) throws {
    self.vault = vault
    tokens = try vault.load()
    preferences = try vault.preferences()
  }

  private init() {
    do {
      #if DEBUG

        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
          let root = FileManager.default.temporaryDirectory.appendingPathComponent("TickKey-UI-" + UUID().uuidString)
          vault = try Vault(directory: root, testKey: Data(repeating: 7, count: 32))
        } else {
          vault = try Vault()
        }
      #else
        vault = try Vault()
      #endif

      guard let vault else {
        throw TickKeyError.storage
      }
      tokens = try vault.load()
      preferences = try vault.preferences()
      Localization.language = preferences.language
    } catch {
      startupError = error
    }
  }

  /// 在现有账户及本次导入内部同时去重，新条目重新分配 UUID，最后统一保存。
  func add(_ imported: [Token]) throws -> (added: Int, duplicates: Int) {
    let merged = try Self.merge(imported, into: tokens)
    let added = merged.tokens.count - tokens.count
    try persist(merged.tokens)
    return (added, merged.duplicates)
  }

  /// 校验和去重不访问主线程模型，供同步编辑和后台批量导入共用。
  private nonisolated static func merge(_ imported: [Token], into existing: [Token]) throws
    -> (tokens: [Token], duplicates: Int) {
    var updated = existing
    var identities = Set(existing.map(\.identity))
    var duplicates = 0

    for var token in imported {
      try token.validate()

      if !identities.insert(token.identity).inserted {
        duplicates += 1
        continue
      }
      token.id = UUID()
      updated.append(token)
    }

    return (updated, duplicates)
  }

  /// iOS 批量导入的校验、加密和数据库事务均在后台完成，成功后才发布新状态。
  func importTokens(_ imported: [Token], completion: @escaping (Result<String, Error>) -> Void) {
    guard let vault, startupError == nil, !importing else {
      completion(.failure(TickKeyError.storage))
      return
    }
    importing = true
    let existing = tokens
    importQueue.async {
      let result = Result {
        let merged = try PerformanceDiagnostics.measure("import.merge", count: imported.count) {
          try Self.merge(imported, into: existing)
        }
        try PerformanceDiagnostics.measure("import.persist", count: merged.tokens.count) {
          try vault.save(merged.tokens)
        }
        return merged
      }
      DispatchQueue.main.async {
        self.importing = false
        completion(result.map { merged in
          self.tokens = merged.tokens
          return String(
            format: Localization.text("import.result"),
            merged.tokens.count - existing.count,
            merged.duplicates)
        })
      }
    }
  }

  /// 把整批导入结果转为本地化反馈，分别显示新增与完全重复的数量。
  func importTokens(_ imported: [Token]) throws -> String {
    let before = tokens.count
    let result = try add(imported)

    return String(format: Localization.text("import.result"), tokens.count - before, result.duplicates)
  }

  /// 编辑保留本地 UUID，并阻止修改后与另一条账户完全重复。
  func update(_ token: Token) throws {
    guard let index = tokens.firstIndex(where: { $0.id == token.id }) else {
      throw TickKeyError.invalidToken
    }

    guard !tokens.contains(where: { $0.id != token.id && $0.sameIdentity(as: token) })
    else {
      throw TickKeyError.duplicate
    }

    var updated = tokens
    updated[index] = token
    try persist(updated)
  }

  /// 删除指定本地账户，保存成功后再发布新的账户列表。
  func delete(_ token: Token) throws {
    try persist(tokens.filter { $0.id != token.id })
  }

  /// 先保存偏好，再更新本地化和订阅者，使语言与外观可以即时切换。
  func setPreferences(_ value: Preferences) throws {
    guard let vault, startupError == nil else {
      throw TickKeyError.storage
    }
    try vault.savePreferences(value)
    Localization.language = value.language
    preferences = value
  }

  /// 启动读取失败时禁止写回；数据库保存成功后才替换内存状态。
  private func persist(_ updated: [Token]) throws {
    // 后台导入持有旧快照时拒绝交错编辑，避免完成回写覆盖较新的账户状态。
    guard let vault, startupError == nil, !importing else {
      throw TickKeyError.storage
    }
    try PerformanceDiagnostics.measure("vault.persist", count: updated.count) { try vault.save(updated) }
    tokens = updated
  }
}
