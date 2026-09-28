import Foundation

// MARK: - GoogleMigration

/// 解析和生成 Google Authenticator 的离线迁移二维码（MigrationPayload protobuf）。
internal enum GoogleMigration {
  private static let scheme = "otpauth-migration"
  private static let maximumPayloadSize = 64 * 1024
  private static let maximumQRLength = 2000

  struct Batch {
    let tokens: [Token]
    let size: Int
    let index: Int
    let id: Int
  }

  static func isMigration(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(scheme + ":")
  }

  /// 对每个账户做完整校验；未知字段按 protobuf 规则跳过，未知账户类型不被误当成 TOTP。
  static func parse(_ text: String) throws -> Batch {
    guard let url = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          url.scheme?.lowercased() == scheme, url.host?.lowercased() == "offline",
          url.path.isEmpty, url.fragment == nil,
          let items = url.queryItems, items.count == 1, items[0].name == "data",
          let encoded = items[0].value,
          let data = Data(base64Encoded: encoded), !data.isEmpty, data.count <= maximumPayloadSize else {
      throw TickKeyError.invalidURI
    }
    var reader = Reader(data)
    var payload = PayloadFields()
    while let field = try reader.next() {
      try payload.accept(field)
    }
    let size = payload.size ?? 1
    let index = payload.index ?? 0
    let id = payload.id ?? 0
    guard !payload.tokens.isEmpty, payload.version == 1 || payload.version == 2,
          (1 ... 10000).contains(size), index < size,
          id <= UInt32.max || id >= UInt64.max - UInt64(Int32.max) else {
      throw TickKeyError.invalidURI
    }
    return Batch(
      tokens: payload.tokens,
      size: Int(size),
      index: Int(index),
      id: Int(UInt32(truncatingIfNeeded: id)))
  }

  /// 单个二维码有容量上限；生成 Google 可识别的批次编号和页码。
  static func encode(_ tokens: [Token]) throws -> [String] {
    guard !tokens.isEmpty, tokens.count <= 10000 else {
      throw TickKeyError.unsupportedFormat
    }
    let entries = try tokens.map(encodeToken)
    let batchID = UInt64(UInt32.random(in: 1 ... UInt32.max))
    var groups: [[Data]] = [[]]
    for entry in entries {
      let candidate = groups[groups.count - 1] + [entry]
      if candidate.count > 10 || uri(candidate, size: 10000, index: 9999, id: batchID).utf8.count > maximumQRLength {
        guard !groups[groups.count - 1].isEmpty else {
          throw TickKeyError.unsupportedFormat
        }
        groups.append([entry])
        guard uri([entry], size: 10000, index: 9999, id: batchID).utf8.count <= maximumQRLength else {
          throw TickKeyError.unsupportedFormat
        }
      } else {
        groups[groups.count - 1] = candidate
      }
    }
    guard groups.count <= 10000 else {
      throw TickKeyError.unsupportedFormat
    }
    return groups.enumerated().map { uri($0.element, size: groups.count, index: $0.offset, id: batchID) }
  }

  private static func parseToken(_ data: Data) throws -> Token {
    var reader = Reader(data)
    var fields = TokenFields()
    while let field = try reader.next() {
      try fields.accept(field)
    }
    return try fields.token()
  }

  private static func algorithm(_ value: UInt64) throws -> OTPAlgorithm {
    return switch value {
    case 0,
         1:
      .sha1
    case 2:
      .sha256
    case 3:
      .sha512
    default:
      throw TickKeyError.unsupportedFormat
    }
  }

  private static func digits(_ value: UInt64) throws -> Int {
    return switch value {
    case 0,
         1:
      6
    case 2:
      8
    default:
      throw TickKeyError.unsupportedFormat
    }
  }

  private static func encodeToken(_ token: Token) throws -> Data {
    try token.validate()
    guard token.period == 30, token.digits == 6 || token.digits == 8 else {
      throw TickKeyError.googleExport
    }
    var data = Data()
    try data.append(bytes: 1, Base32.decode(token.secret))
    data.append(bytes: 2, Data(token.account.utf8))
    data.append(bytes: 3, Data(token.issuer.utf8))
    let algorithm: UInt64 = switch token.algorithm {
    case .sha1:
      1
    case .sha256:
      2
    case .sha512:
      3
    }
    data.append(number: 4, algorithm)
    data.append(number: 5, token.digits == 6 ? 1 : 2)
    data.append(number: 6, 2)
    return data
  }

  private static func uri(_ entries: [Data], size: Int, index: Int, id: UInt64) -> String {
    var payload = Data()
    for entry in entries {
      payload.append(bytes: 1, entry)
    }
    payload.append(number: 2, 1)
    payload.append(number: 3, UInt64(size))
    payload.append(number: 4, UInt64(index))
    payload.append(number: 5, id)
    var url = URLComponents()
    url.scheme = scheme
    url.host = "offline"
    url.queryItems = [URLQueryItem(name: "data", value: payload.base64EncodedString())]
    return url.string ?? ""
  }

  private enum Value {
    case number(UInt64)
    case bytes(Data)
    case other
  }

  private struct Field {
    let number: Int
    let value: Value

    func bytes() throws -> Data {
      guard case let .bytes(data) = value else {
        throw TickKeyError.invalidURI
      }
      return data
    }

    func numberValue() throws -> UInt64 {
      guard case let .number(number) = value else {
        throw TickKeyError.invalidURI
      }
      return number
    }

    func string() throws -> String {
      guard let text = try String(data: bytes(), encoding: .utf8) else {
        throw TickKeyError.invalidURI
      }
      return text
    }
  }

  private struct PayloadFields {
    var tokens: [Token] = []
    var version: UInt64?
    var size: UInt64?
    var index: UInt64?
    var id: UInt64?
    private var seen = Set<Int>()

    mutating func accept(_ field: Field) throws {
      if field.number == 1 {
        guard case let .bytes(bytes) = field.value, tokens.count < 100 else {
          throw TickKeyError.invalidURI
        }
        try tokens.append(parseToken(bytes))
        return
      }
      guard field.number >= 2, field.number <= 5 else {
        return
      }
      guard seen.insert(field.number).inserted, case let .number(value) = field.value else {
        throw TickKeyError.invalidURI
      }
      switch field.number {
      case 2:
        version = value
      case 3:
        size = value
      case 4:
        index = value
      default:
        id = value
      }
    }
  }

  private struct TokenFields {
    var secret: Data?
    var name: String?
    var issuer = ""
    var algorithm: UInt64 = 1
    var digits: UInt64 = 1
    var type: UInt64?
    private var seen = Set<Int>()

    mutating func accept(_ field: Field) throws {
      guard (1 ... 7).contains(field.number) else {
        return
      }
      guard seen.insert(field.number).inserted else {
        throw TickKeyError.invalidURI
      }
      switch field.number {
      case 1:
        secret = try field.bytes()
      case 2:
        name = try field.string()
      case 3:
        issuer = try field.string()
      case 4:
        algorithm = try field.numberValue()
      case 5:
        digits = try field.numberValue()
      case 6:
        type = try field.numberValue()
      default:
        _ = try field.numberValue()
      }
    }

    func token() throws -> Token {
      guard type == 2, let secret, !secret.isEmpty, let name else {
        throw TickKeyError.unsupportedFormat
      }
      return try Token(
        issuer: issuer,
        account: name,
        secret: Base32.encode(secret),
        algorithm: GoogleMigration.algorithm(algorithm),
        digits: GoogleMigration.digits(digits))
    }
  }

  /// 只读取 protobuf 标准 wire types，边界和 varint 溢出均视为损坏输入。
  private struct Reader {
    let data: Data
    var offset = 0

    init(_ data: Data) {
      self.data = data
    }

    mutating func next() throws -> Field? {
      guard offset < data.count else {
        return nil
      }
      let tag = try varint()
      guard tag > 0, tag >> 3 <= Int.max, tag >> 3 > 0 else {
        throw TickKeyError.invalidURI
      }
      let number = Int(tag >> 3)
      switch tag & 7 {
      case 0:
        return try Field(number: number, value: .number(varint()))
      case 1:
        try skip(8)
        return Field(number: number, value: .other)
      case 2:
        let length = try varint()
        guard length <= UInt64(data.count - offset) else {
          throw TickKeyError.invalidURI
        }
        let end = offset + Int(length)
        let bytes = data.subdata(in: offset ..< end)
        offset = end
        return Field(number: number, value: .bytes(bytes))
      case 5:
        try skip(4)
        return Field(number: number, value: .other)
      default:
        throw TickKeyError.invalidURI
      }
    }

    private mutating func skip(_ count: Int) throws {
      guard data.count - offset >= count else {
        throw TickKeyError.invalidURI
      }
      offset += count
    }

    private mutating func varint() throws -> UInt64 {
      var value: UInt64 = 0
      for shift in stride(from: 0, through: 63, by: 7) {
        guard offset < data.count else {
          throw TickKeyError.invalidURI
        }
        let byte = data[offset]
        offset += 1
        guard shift != 63 || byte <= 1 else {
          throw TickKeyError.invalidURI
        }
        value |= UInt64(byte & 0x7F) << shift
        if byte & 0x80 == 0 {
          return value
        }
      }
      throw TickKeyError.invalidURI
    }
  }
}

private extension Data {
  mutating func append(number field: UInt8, _ value: UInt64) {
    appendVarint(UInt64(field) << 3)
    appendVarint(value)
  }

  mutating func append(bytes field: UInt8, _ value: Data) {
    appendVarint(UInt64(field) << 3 | 2)
    appendVarint(UInt64(value.count))
    append(value)
  }

  mutating func appendVarint(_ value: UInt64) {
    var remaining = value
    while remaining >= 128 {
      append(UInt8(remaining & 0x7F) | 0x80)
      remaining >>= 7
    }
    append(UInt8(remaining))
  }
}
