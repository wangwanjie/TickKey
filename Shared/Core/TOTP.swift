import Foundation
import CryptoKit

/// RFC 6238：每次由绝对时间计算，避免定时器暂停造成验证码漂移。
enum TOTP {
    static func code(for token: Token, at date: Date = Date()) throws -> String {
        try token.validate()
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds >= 0, seconds < Double(UInt64.max) else { throw TickKeyError.invalidToken }
        var counter = UInt64(seconds / Double(token.period)).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let key = SymmetricKey(data: try Base32.decode(token.secret))
        let digest: [UInt8]
        switch token.algorithm {
        case .sha1: digest = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: digest = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: digest = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        let offset = Int(digest[digest.count - 1] & 15)
        let number = digest[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } & 0x7fffffff
        let divisor = (0..<token.digits).reduce(UInt32(1)) { value, _ in value * 10 }
        return String(format: "%0*u", token.digits, number % divisor)
    }
    static func remainingFraction(for token: Token, at date: Date = Date()) -> Double {
        1 - date.timeIntervalSince1970.truncatingRemainder(dividingBy: Double(token.period)) / Double(token.period)
    }
    static func display(_ code: String) -> String {
        let index = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<index]) + " " + String(code[index...])
    }
}
