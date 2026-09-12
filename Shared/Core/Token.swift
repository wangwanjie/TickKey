import Foundation

// MARK: - OTPAlgorithm

/// 协议中的算法名称保持稳定，直接用于 URI 与备份编码。
internal enum OTPAlgorithm: String, Codable, CaseIterable {
  case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512"
}

// MARK: - TickKeyError

/// 统一业务错误，只提供本地化说明，不在提示中泄露密钥或备份内容。
internal enum TickKeyError: LocalizedError {
  case invalidSecret, invalidToken, invalidURI, unsupportedFormat, invalidPassword, damagedBackup, storage, duplicate
  case invalidLine(Int)

  var errorDescription: String? {
    switch self {
    case .invalidSecret:
      Localization.text("error.secret")
    case .invalidToken:
      Localization.text("error.token")
    case .invalidURI:
      Localization.text("error.uri")
    case .unsupportedFormat:
      Localization.text("error.format")
    case .invalidPassword:
      Localization.text("error.password")
    case .damagedBackup:
      Localization.text("error.backup")
    case .storage:
      Localization.text("error.storage")
    case .duplicate:
      Localization.text("error.duplicate")
    case let .invalidLine(line):
      String(format: Localization.text("error.line"), line)
    }
  }
}

// MARK: - Token

/// 身份字段不含本地 UUID；仅全部录入字段一致时去重。
internal struct Token: Codable, Identifiable, Equatable {
  /// 使用结构化身份建立哈希集合，避免批量导入的逐项全表扫描；不参与备份编码。
  struct Identity: Hashable {
    let issuer: String
    let account: String
    let secret: String
    let algorithm: String
    let digits: Int
    let period: Int
  }

  var identity: Identity {
    Identity(
      issuer: issuer,
      account: account,
      secret: secret,
      algorithm: algorithm.rawValue,
      digits: digits,
      period: period)
  }

  var id: UUID
  var issuer: String
  var account: String
  var secret: String
  var algorithm: OTPAlgorithm
  var digits: Int
  var period: Int

  init(
    id: UUID = UUID(),
    issuer: String,
    account: String,
    secret: String,
    algorithm: OTPAlgorithm = .sha1,
    digits: Int = 6,
    period: Int = 30) throws {
    self.id = id
    self.issuer = issuer
    self.account = account
    self.secret = Base32.normalize(secret)
    self.algorithm = algorithm
    self.digits = digits
    self.period = period
    try validate()
  }

  /// 检查名称、验证码参数与 Base32 密钥，发行方和账户名至少一项有内容。
  func validate() throws {
    // 浏览器验证器允许只填写发行方；保留空账户名，避免补造名称改变去重身份。
    guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      account.count <= 256, issuer.count <= 256,
      (6 ... 8).contains(digits), (1 ... 300).contains(period),
      !account.contains(where: \.isNewline), !issuer.contains(where: \.isNewline)
    else {
      throw TickKeyError.invalidToken
    }

    guard secret.count <= 1024, try !(Base32.decode(secret)).isEmpty else {
      throw TickKeyError.invalidSecret
    }
  }

  /// 比较全部录入字段，忽略本地 UUID；空账户名与任何补填名称均视为不同身份。
  func sameIdentity(as other: Self) -> Bool {
    identity == other.identity
  }

  var title: String {
    issuer.isEmpty ? account : issuer
  }

  /// 只搜索发行方和账户名称，避免把密钥暴露到搜索行为中。
  func matches(_ query: String) -> Bool {
    query.isEmpty || issuer.localizedStandardContains(query) || account.localizedStandardContains(query)
  }
}

// MARK: - Base32

/// 实现 RFC 4648 Base32 编解码，接受无填充形式并拒绝无效尾部位。
internal enum Base32 {
  private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

  /// 只规范化密钥的大小写和空白，不改写用户录入的发行方或账户名称。
  static func normalize(_ string: String) -> String {
    string.uppercased().filter { !$0.isWhitespace }
  }

  /// 将五位字符流还原为字节，同时校验长度、填充和未使用的尾部位。
  static func decode(_ string: String) throws -> Data {
    let value = normalize(string)
    let body = String(value.prefix { $0 != "=" })
    let padding = value.count - body.count

    guard !body.isEmpty, value.dropFirst(body.count).allSatisfy({ $0 == "=" }),
          [0, 2, 4, 5, 7].contains(body.count % 8),
          padding == 0 || (value.count % 8 == 0 && padding < 7) else {
      throw TickKeyError.invalidSecret
    }

    // 每个字符贡献五位，累计到一个字节后输出。
    var buffer: UInt32 = 0
    var bits = 0
    var output = Data()

    for character in body {
      guard let index = alphabet.firstIndex(of: character) else {
        throw TickKeyError.invalidSecret
      }
      buffer = (buffer << 5) | UInt32(index)
      bits += 5

      if bits >= 8 {
        bits -= 8
        output.append(UInt8((buffer >> bits) & 255))
      }
    }

    // 未使用的尾部位必须为零，拒绝不规范编码或损坏的密钥。
    guard bits == 0 || buffer & ((1 << bits) - 1) == 0 else {
      throw TickKeyError.invalidSecret
    }

    return output
  }

  /// 将字节流编码为不带填充的 Base32，主要用于标准样例及互通验证。
  static func encode(_ data: Data) -> String {
    var buffer: UInt32 = 0
    var bits = 0
    var result = ""

    for byte in data {
      buffer = (buffer << 8) | UInt32(byte)
      bits += 8
      while bits >= 5 {
        bits -= 5
        result.append(alphabet[Int((buffer >> bits) & 31)])
      }
    }

    if bits > 0 {
      result.append(alphabet[Int((buffer << (5 - bits)) & 31)])
    }

    return result
  }
}
