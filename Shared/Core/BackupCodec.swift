import CommonCrypto
import CryptoKit
import Foundation
import Security

/// 公开的版本化容器：PBKDF2-HMAC-SHA256 + AES-256-GCM，不保存密码。
internal enum BackupCodec {
  static let maximumSize = 16 * 1024 * 1024
  static let rounds = 600_000
  private static let header = Data("TickKey/1\n".utf8)

  private struct Envelope: Codable {
    let version: Int
    let rounds: Int
    let salt: Data
    let sealed: Data
  }

  /// 根据文件内容识别 TickKey 容器，不依赖扩展名；未知版本交给解码器明确拒绝。
  static func isEncrypted(_ data: Data) -> Bool {
    data.starts(with: Data("TickKey/".utf8))
  }

  /// 以每行一条 otpauth URI 导出；任何无效账户都会中止整次导出。
  static func text(_ tokens: [Token]) throws -> Data {
    try Data((tokens.map(OTPURI.encode).joined(separator: "\n") + "\n").utf8)
  }

  /// 使用独立随机盐和 nonce 加密完整备份，密码仅参与派生，不写入文件。
  static func encrypt(_ tokens: [Token], password: String) throws -> Data {
    guard password.count >= 10, password.utf8.count <= 1024 else {
      throw TickKeyError.invalidPassword
    }

    // 每次导出使用新的盐；AES.GCM 同时自动生成新的 nonce。
    let salt = try randomBytes(count: 16)
    let key = try derive(password: password, salt: salt)
    let plaintext = try JSONEncoder().encode(tokens)

    guard plaintext.count < maximumSize / 2 else {
      throw TickKeyError.unsupportedFormat
    }

    // 把文件头和盐绑定到认证数据中，修改容器元数据也会导致认证失败。
    guard let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header + salt).combined else {
      throw TickKeyError.storage
    }

    return try header + (JSONEncoder().encode(Envelope(version: 1, rounds: rounds, salt: salt, sealed: sealed)))
  }

  /// 按内容选择解析器并限制文件大小；返回前完成整批校验，调用方再统一持久化。
  static func decode(_ data: Data, password: String? = nil) throws -> [Token] {
    guard data.count <= maximumSize, !data.isEmpty else {
      throw TickKeyError.unsupportedFormat
    }

    if isEncrypted(data) {
      return try decodeEncrypted(data, password: password)
    }

    return try decodeText(data)
  }

  /// 先验证容器参数，再验证 GCM 认证标签；错误密码与损坏备份统一返回认证失败。
  private static func decodeEncrypted(_ data: Data, password: String?) throws -> [Token] {
    guard data.starts(with: header) else {
      throw TickKeyError.unsupportedFormat
    }

    guard let password, !password.isEmpty, password.utf8.count <= 1024 else {
      throw TickKeyError.invalidPassword
    }

    do {
      let envelope = try JSONDecoder().decode(Envelope.self, from: data.dropFirst(header.count))

      // 在执行耗时派生前限制参数，防止恶意文件放大计算开销。
      guard envelope.version == 1, envelope.rounds == rounds, envelope.salt.count == 16,
            envelope.sealed.count >= 28 else {
        throw TickKeyError.damagedBackup
      }

      let key = try derive(password: password, salt: envelope.salt)
      let plain = try AES.GCM.open(
        AES.GCM.SealedBox(combined: envelope.sealed),
        using: key,
        authenticating: header + envelope.salt)
      let tokens = try JSONDecoder().decode([Token].self, from: plain)

      guard tokens.count <= 10000 else {
        throw TickKeyError.unsupportedFormat
      }

      // Codable 解码不会经过自定义初始化器，需要逐项重新验证。
      return try tokens.map { token in
        try Token(
          id: token.id,
          issuer: token.issuer,
          account: token.account,
          secret: token.secret,
          algorithm: token.algorithm,
          digits: token.digits,
          period: token.period)
      }
    } catch {
      throw TickKeyError.damagedBackup
    }
  }

  /// 接受 BOM、空行和不同换行符，遇到无效记录时只报告行号，不输出原始内容。
  private static func decodeText(_ data: Data) throws -> [Token] {
    guard var string = String(data: data, encoding: .utf8) else {
      throw TickKeyError.unsupportedFormat
    }

    if string.hasPrefix("\u{feff}") {
      string.removeFirst()
    }

    var tokens: [Token] = []

    for (index, line) in string.components(separatedBy: .newlines).enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty {
        continue
      }

      do {
        try tokens.append(OTPURI.parse(trimmed))
      } catch {
        throw TickKeyError.invalidLine(index + 1)
      }
    }

    guard !tokens.isEmpty, tokens.count <= 10000 else {
      throw TickKeyError.unsupportedFormat
    }

    return tokens
  }

  /// 从系统安全随机源获取字节；失败时中止操作，禁止退回可预测随机数。
  static func randomBytes(count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)

    guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
      throw TickKeyError.storage
    }

    return Data(bytes)
  }

  /// 通过 PBKDF2-HMAC-SHA256 派生 256 位密钥，迭代次数固定为协议规定值。
  private static func derive(password: String, salt: Data) throws -> SymmetricKey {
    let passwordBytes = Array(password.utf8)
    var key = [UInt8](repeating: 0, count: 32)
    let status = passwordBytes.withUnsafeBytes { passwordBuffer in
      salt.withUnsafeBytes { saltBuffer in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2),
          passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self),
          passwordBytes.count,
          saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
          salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
          UInt32(rounds),
          &key,
          key.count)
      }
    }

    guard status == kCCSuccess else {
      throw TickKeyError.storage
    }

    return SymmetricKey(data: key)
  }
}
