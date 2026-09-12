import Foundation

enum OTPURI {
    static func parse(_ string: String) throws -> Token {
        guard let url = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "otpauth", url.host?.lowercased() == "totp",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              url.path.hasPrefix("/") else { throw TickKeyError.invalidURI }
        var fields: [String: String] = [:]
        for item in url.queryItems ?? [] {
            guard fields[item.name] == nil, let value = item.value else { throw TickKeyError.invalidURI }
            fields[item.name] = value
        }
        let encodedLabel = String(url.percentEncodedPath.dropFirst())
        let parts = encodedLabel.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map {
            ($0.description.removingPercentEncoding ?? $0.description)
        }
        let label = parts.joined(separator: ":")
        let prefix = parts.count == 2 ? String(parts[0]) : ""
        if let issuer = fields["issuer"], !prefix.isEmpty, issuer != prefix { throw TickKeyError.invalidURI }
        guard let secret = fields["secret"],
              let algorithm = OTPAlgorithm(rawValue: (fields["algorithm"] ?? "SHA1").uppercased()),
              let digits = Int(fields["digits"] ?? "6"), let period = Int(fields["period"] ?? "30") else { throw TickKeyError.invalidURI }
        return try Token(issuer: fields["issuer"] ?? prefix,
                         account: parts.count == 2 ? String(parts[1]) : label,
                         secret: secret, algorithm: algorithm, digits: digits, period: period)
    }
    static func encode(_ token: Token) -> String {
        var url = URLComponents()
        url.scheme = "otpauth"; url.host = "totp"
        // 不把 issuer 拼入 label，避免发行方名称中的冒号产生歧义。
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        url.percentEncodedPath = "/" + (token.account.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        url.queryItems = [URLQueryItem(name: "secret", value: token.secret),
                          URLQueryItem(name: "issuer", value: token.issuer),
                          URLQueryItem(name: "algorithm", value: token.algorithm.rawValue),
                          URLQueryItem(name: "digits", value: String(token.digits)),
                          URLQueryItem(name: "period", value: String(token.period))]
        return url.string!
    }
}
