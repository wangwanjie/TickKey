import Foundation
import CryptoKit
import CommonCrypto
import Security

/// 公开的版本化容器：PBKDF2-HMAC-SHA256 + AES-256-GCM，不保存密码。
enum BackupCodec {
    static let maximumSize = 16 * 1024 * 1024
    static let rounds = 600_000
    private static let header = Data("TickKey/1\n".utf8)
    private struct Envelope: Codable {
        let version: Int
        let rounds: Int
        let salt: Data
        let sealed: Data
    }
    static func isEncrypted(_ data: Data) -> Bool { data.starts(with: Data("TickKey/".utf8)) }
    static func text(_ tokens: [Token]) -> Data {
        Data((tokens.map(OTPURI.encode).joined(separator: "\n") + "\n").utf8)
    }
    static func encrypt(_ tokens: [Token], password: String) throws -> Data {
        guard password.count >= 10, password.utf8.count <= 1024 else { throw TickKeyError.invalidPassword }
        let salt = try randomBytes(count: 16)
        let key = try derive(password: password, salt: salt)
        let plaintext = try JSONEncoder().encode(tokens)
        guard plaintext.count < maximumSize / 2 else { throw TickKeyError.unsupportedFormat }
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header + salt).combined!
        return header + (try JSONEncoder().encode(Envelope(version: 1, rounds: rounds, salt: salt, sealed: sealed)))
    }
    static func decode(_ data: Data, password: String? = nil) throws -> [Token] {
        guard data.count <= maximumSize, !data.isEmpty else { throw TickKeyError.unsupportedFormat }
        if isEncrypted(data) {
            guard data.starts(with: header) else { throw TickKeyError.unsupportedFormat }
            guard let password, !password.isEmpty, password.utf8.count <= 1024 else { throw TickKeyError.invalidPassword }
            do {
                let envelope = try JSONDecoder().decode(Envelope.self, from: data.dropFirst(header.count))
                guard envelope.version == 1, envelope.rounds == rounds, envelope.salt.count == 16,
                      envelope.sealed.count >= 28 else { throw TickKeyError.damagedBackup }
                let key = try derive(password: password, salt: envelope.salt)
                let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key,
                                             authenticating: header + envelope.salt)
                let tokens = try JSONDecoder().decode([Token].self, from: plain)
                guard tokens.count <= 10_000 else { throw TickKeyError.unsupportedFormat }
                return try tokens.map { token in
                    try Token(id: token.id, issuer: token.issuer, account: token.account, secret: token.secret,
                              algorithm: token.algorithm, digits: token.digits, period: token.period)
                }
            } catch { throw TickKeyError.damagedBackup }
        }
        guard var string = String(data: data, encoding: .utf8) else { throw TickKeyError.unsupportedFormat }
        if string.hasPrefix("\u{feff}") { string.removeFirst() }
        var tokens: [Token] = []
        for (index, line) in string.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            do { tokens.append(try OTPURI.parse(trimmed)) }
            catch { throw TickKeyError.invalidLine(index + 1) }
        }
        guard !tokens.isEmpty, tokens.count <= 10_000 else { throw TickKeyError.unsupportedFormat }
        return tokens
    }
    static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw TickKeyError.storage }
        return Data(bytes)
    }
    private static func derive(password: String, salt: Data) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var key = [UInt8](repeating: 0, count: 32)
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self), passwordBytes.count,
                    saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds), &key, key.count)
            }
        }
        guard status == kCCSuccess else { throw TickKeyError.storage }
        return SymmetricKey(data: key)
    }
}
