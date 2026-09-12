import Foundation

enum OTPAlgorithm: String, Codable, CaseIterable {
    case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512"
}

enum TickKeyError: LocalizedError {
    case invalidSecret, invalidToken, invalidURI, unsupportedFormat, invalidPassword, damagedBackup, storage, duplicate
    case invalidLine(Int)
    var errorDescription: String? {
        switch self {
        case .invalidSecret: return L.text("error.secret")
        case .invalidToken: return L.text("error.token")
        case .invalidURI: return L.text("error.uri")
        case .unsupportedFormat: return L.text("error.format")
        case .invalidPassword: return L.text("error.password")
        case .damagedBackup: return L.text("error.backup")
        case .storage: return L.text("error.storage")
        case .duplicate: return L.text("error.duplicate")
        case .invalidLine(let line): return String(format: L.text("error.line"), line)
        }
    }
}

/// 身份字段不含本地 UUID；仅全部录入字段一致时去重。
struct Token: Codable, Identifiable, Equatable {
    var id: UUID
    var issuer: String
    var account: String
    var secret: String
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int

    init(id: UUID = UUID(), issuer: String, account: String, secret: String,
         algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30) throws {
        self.id = id
        self.issuer = issuer
        self.account = account
        self.secret = Base32.normalize(secret)
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        try validate()
    }

    func validate() throws {
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              account.count <= 256, issuer.count <= 256,
              (6...8).contains(digits), (1...300).contains(period),
              !account.contains(where: { $0.isNewline }), !issuer.contains(where: { $0.isNewline }) else {
            throw TickKeyError.invalidToken
        }
        guard secret.count <= 1024, !(try Base32.decode(secret)).isEmpty else { throw TickKeyError.invalidSecret }
    }

    func sameIdentity(as other: Token) -> Bool {
        issuer == other.issuer && account == other.account && secret == other.secret &&
        algorithm == other.algorithm && digits == other.digits && period == other.period
    }

    var title: String { issuer.isEmpty ? account : issuer }
    func matches(_ query: String) -> Bool {
        query.isEmpty || issuer.localizedStandardContains(query) || account.localizedStandardContains(query)
    }
}

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    static func normalize(_ string: String) -> String {
        string.uppercased().filter { !$0.isWhitespace }
    }
    static func decode(_ string: String) throws -> Data {
        let value = normalize(string)
        let body = String(value.prefix { $0 != "=" })
        let padding = value.count - body.count
        guard !body.isEmpty, value.dropFirst(body.count).allSatisfy({ $0 == "=" }),
              [0, 2, 4, 5, 7].contains(body.count % 8),
              padding == 0 || (value.count % 8 == 0 && padding < 7) else { throw TickKeyError.invalidSecret }
        var buffer: UInt32 = 0, bits = 0
        var output = Data()
        for character in body {
            guard let index = alphabet.firstIndex(of: character) else { throw TickKeyError.invalidSecret }
            buffer = (buffer << 5) | UInt32(index)
            bits += 5
            if bits >= 8 { bits -= 8; output.append(UInt8((buffer >> bits) & 255)) }
        }
        guard bits == 0 || buffer & ((1 << bits) - 1) == 0 else { throw TickKeyError.invalidSecret }
        return output
    }
    static func encode(_ data: Data) -> String {
        var buffer: UInt32 = 0, bits = 0, result = ""
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte); bits += 8
            while bits >= 5 { bits -= 5; result.append(alphabet[Int((buffer >> bits) & 31)]) }
        }
        if bits > 0 { result.append(alphabet[Int((buffer << (5 - bits)) & 31)]) }
        return result
    }
}
