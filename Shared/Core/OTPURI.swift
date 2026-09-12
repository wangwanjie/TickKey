import Foundation

/// 负责标准 otpauth URI 与本地账户模型之间的无损转换。
internal enum OTPURI {
  /// 校验 TOTP 协议、重复参数和发行方一致性，保留浏览器备份中的空账户名。
  static func parse(_ string: String) throws -> Token {
    guard let url = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
          url.scheme?.lowercased() == "otpauth", url.host?.lowercased() == "totp",
          url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
          url.path.hasPrefix("/") else {
      throw TickKeyError.invalidURI
    }

    var fields: [String: String] = [:]

    for item in url.queryItems ?? [] {
      guard fields[item.name] == nil, let value = item.value else {
        throw TickKeyError.invalidURI
      }
      fields[item.name] = value
    }

    let encodedLabel = String(url.percentEncodedPath.dropFirst())
    let parts = encodedLabel.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map {
      $0.description.removingPercentEncoding ?? $0.description
    }

    let label = parts.joined(separator: ":")
    let prefix = parts.count == 2 ? String(parts[0]) : ""

    if let issuer = fields["issuer"], !prefix.isEmpty, issuer != prefix {
      throw TickKeyError.invalidURI
    }

    guard let secret = fields["secret"],
          let algorithm = OTPAlgorithm(rawValue: (fields["algorithm"] ?? "SHA1").uppercased()),
          let digits = Int(fields["digits"] ?? "6"),
          let period = Int(fields["period"] ?? "30") else {
      throw TickKeyError.invalidURI
    }

    return try Token(
      issuer: fields["issuer"] ?? prefix,
      account: parts.count == 2 ? String(parts[1]) : label,
      secret: secret,
      algorithm: algorithm,
      digits: digits,
      period: period)
  }

  /// 生成可供外部验证器导入的 URI；模型无效时抛错，避免导出无法恢复的条目。
  static func encode(_ token: Token) throws -> String {
    try token.validate()
    var url = URLComponents()
    url.scheme = "otpauth"
    url.host = "totp"
    // 有账户名时不拼入发行方；空账户名保留浏览器验证器的「发行方:」写法。
    // 发行方自身的冒号需要编码，以区别于账户分隔符。
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let label = token.account.isEmpty
      ? (token.issuer.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + ":"
      : (token.account.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    url.percentEncodedPath = "/" + label
    url.queryItems = [
      URLQueryItem(name: "secret", value: token.secret),
      URLQueryItem(name: "issuer", value: token.issuer),
      URLQueryItem(name: "algorithm", value: token.algorithm.rawValue),
      URLQueryItem(name: "digits", value: String(token.digits)),
      URLQueryItem(name: "period", value: String(token.period))
    ]

    guard let string = url.string else {
      throw TickKeyError.invalidURI
    }

    return string
  }
}
