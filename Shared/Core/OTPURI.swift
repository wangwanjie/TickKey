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
    let prefix = parts.count == 2 ? parts[0].trimmingCharacters(in: .whitespaces) : ""
    // Key URI 规范允许「发行方:」后带可选空格，账户名只去掉这部分前导分隔空白。
    let account = parts.count == 2 ? String(parts[1].drop { $0 == " " }) : label

    if let issuer = fields["issuer"], !prefix.isEmpty,
       issuer.trimmingCharacters(in: .whitespaces) != prefix {
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
      account: account,
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
    // 按 Key URI 规范同时写入「发行方:账户」标签和 issuer 参数，兼容只读取标签前缀的旧验证器；
    // 空账户名保留浏览器验证器的「发行方:」写法，无发行方时只写账户名。
    // 发行方自身的冒号需要编码，以区别于账户分隔符。
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~@"))
    let issuer = token.issuer.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    let account = token.account.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    // 账户名以空格开头时不加前缀，否则解析端会把空格视为分隔空白，导致往返后身份变化。
    let label = token.issuer.isEmpty || token.account.hasPrefix(" ") ? account : issuer + ":" + account
    url.percentEncodedPath = "/" + label
    var items = [URLQueryItem(name: "secret", value: token.secret)]

    // 空发行方不写参数，避免外部验证器显示空白发行方。
    // 参数值严格编码，「+」「&」等字符不会被其他验证器按表单规则误解为空格或分隔符。
    if !token.issuer.isEmpty {
      items.append(URLQueryItem(name: "issuer", value: issuer))
    }
    items += [
      URLQueryItem(name: "algorithm", value: token.algorithm.rawValue),
      URLQueryItem(name: "digits", value: String(token.digits)),
      URLQueryItem(name: "period", value: String(token.period))
    ]
    url.percentEncodedQueryItems = items

    guard let string = url.string else {
      throw TickKeyError.invalidURI
    }

    return string
  }
}
