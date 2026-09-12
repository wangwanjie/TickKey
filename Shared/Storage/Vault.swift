import Foundation
import CryptoKit
import Security
import GRDB
import Combine
import MMKV

/// Keychain 中保存设备密钥，SQLite 只存认证加密后的完整账户记录。
final class Vault {
    private let db: DatabaseQueue
    private let key: SymmetricKey
    private let settings: MMKV

    init(directory: URL? = nil, testKey: Data? = nil) throws {
        let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TickKey", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        MMKV.initialize(rootDir: root.appendingPathComponent("settings").path)
        guard let settings = MMKV(mmapID: "preferences", rootPath: root.appendingPathComponent("settings").path) else { throw TickKeyError.storage }
        self.settings = settings
        var excluded = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let databaseURL = root.appendingPathComponent("vault.sqlite")
        key = try testKey.map { SymmetricKey(data: $0) } ?? Self.deviceKey(allowCreate: !FileManager.default.fileExists(atPath: databaseURL.path))
        db = try DatabaseQueue(path: databaseURL.path)
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
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: databaseURL.path)
        #endif
    }

    func load() throws -> [Token] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT id, payload FROM tokens ORDER BY position").map { row in
                let id: String = row["id"], payload: Data = row["payload"]
                let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: key, authenticating: Data(id.utf8))
                let token = try JSONDecoder().decode(Token.self, from: plain)
                try token.validate()
                guard token.id.uuidString == id else { throw TickKeyError.storage }
                return token
            }
        }
    }

    func save(_ tokens: [Token]) throws {
        let records = try tokens.enumerated().map { index, token -> (String, Data, Int) in
            try token.validate()
            let id = token.id.uuidString
            let sealed = try AES.GCM.seal(JSONEncoder().encode(token), using: key, authenticating: Data(id.utf8))
            return (id, sealed.combined!, index)
        }
        try db.write { db in
            try db.execute(sql: "DELETE FROM tokens")
            for (id, payload, position) in records {
                try db.execute(sql: "INSERT INTO tokens (id, payload, position) VALUES (?, ?, ?)", arguments: [id, payload, position])
            }
        }
    }

    func preferences() throws -> Preferences {
        let language = settings.string(forKey: "language") ?? "system"
        let appearance = Int(settings.int32(forKey: "appearance"))
        return Preferences(language: ["system", "en", "zh-Hans", "zh-Hant"].contains(language) ? language : "system",
                           appearance: (0...2).contains(appearance) ? appearance : 0)
    }
    func savePreferences(_ value: Preferences) throws {
        guard settings.set(value.language, forKey: "language"), settings.set(Int32(value.appearance), forKey: "appearance") else { throw TickKeyError.storage }
    }
    private static func deviceKey(allowCreate: Bool) throws -> SymmetricKey {
        let service = (Bundle.main.bundleIdentifier ?? "cn.vanjay.TickKey") + ".vault"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "device-key-v1"]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound, allowCreate else { throw TickKeyError.storage }
        let data = try BackupCodec.randomBytes(count: 32)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw TickKeyError.storage }
        return SymmetricKey(data: data)
    }
}

struct Preferences {
    var language = "system"
    var appearance = 0
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var tokens: [Token] = []
    @Published private(set) var preferences = Preferences()
    @Published private(set) var startupError: Error?
    private var vault: Vault?

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
            } else { vault = try Vault() }
            #else
            vault = try Vault()
            #endif
            tokens = try vault!.load()
            preferences = try vault!.preferences()
            L.language = preferences.language
        } catch { startupError = error }
    }
    func add(_ imported: [Token]) throws -> (added: Int, duplicates: Int) {
        var updated = tokens, duplicates = 0
        for var token in imported {
            try token.validate()
            if updated.contains(where: { $0.sameIdentity(as: token) }) { duplicates += 1; continue }
            token.id = UUID()
            updated.append(token)
        }
        let added = updated.count - tokens.count
        try persist(updated)
        return (added, duplicates)
    }
    func importTokens(_ imported: [Token]) throws -> String {
        let before = tokens.count
        let result = try add(imported)
        return String(format: L.text("import.result"), tokens.count - before, result.duplicates)
    }
    func update(_ token: Token) throws {
        guard let index = tokens.firstIndex(where: { $0.id == token.id }) else { throw TickKeyError.invalidToken }
        guard !tokens.contains(where: { $0.id != token.id && $0.sameIdentity(as: token) }) else { throw TickKeyError.duplicate }
        var updated = tokens; updated[index] = token; try persist(updated)
    }
    func delete(_ token: Token) throws { try persist(tokens.filter { $0.id != token.id }) }
    func setPreferences(_ value: Preferences) throws {
        guard let vault, startupError == nil else { throw TickKeyError.storage }
        try vault.savePreferences(value)
        L.language = value.language
        preferences = value
    }
    private func persist(_ updated: [Token]) throws {
        guard let vault, startupError == nil else { throw TickKeyError.storage }
        try vault.save(updated); tokens = updated
    }
}
