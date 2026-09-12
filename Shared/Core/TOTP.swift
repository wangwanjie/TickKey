import CryptoKit
import Foundation

/// RFC 6238：每次由绝对时间计算，避免定时器暂停造成验证码漂移。
internal enum TOTP {
  /// 按 RFC 6238 计算指定时刻的验证码，支持 SHA-1、SHA-256 和 SHA-512。
  static func code(for token: Token, at date: Date = Date()) throws -> String {
    try token.validate()
    let seconds = date.timeIntervalSince1970

    guard seconds.isFinite, seconds >= 0, seconds < Double(UInt64.max) else {
      throw TickKeyError.invalidToken
    }

    // 时间步长必须使用网络字节序参与 HMAC，确保各平台生成相同结果。
    var counter = UInt64(seconds / Double(token.period)).bigEndian
    let message = withUnsafeBytes(of: &counter) { Data($0) }
    let key = try SymmetricKey(data: Base32.decode(token.secret))
    let digest: [UInt8] = switch token.algorithm {
    case .sha1:
      Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
    case .sha256:
      Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
    case .sha512:
      Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
    }

    // RFC 动态截断：由摘要末字节选择偏移，并清除符号位后按位数取模。
    let offset = Int(digest[digest.count - 1] & 15)
    let number = digest[offset ..< (offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } & 0x7FFF_FFFF
    let divisor = (0 ..< token.digits).reduce(UInt32(1)) { value, _ in value * 10 }

    return String(format: "%0*u", token.digits, number % divisor)
  }

  /// 返回当前周期的剩余比例，供圆饼动画使用；不依赖定时器累计次数。
  static func remainingFraction(for token: Token, at date: Date = Date()) -> Double {
    1 - date.timeIntervalSince1970.truncatingRemainder(dividingBy: Double(token.period)) / Double(token.period)
  }

  /// 仅对展示文本分组，复制到剪贴板时仍使用未分组的原始验证码。
  static func display(_ code: String) -> String {
    let index = code.index(code.startIndex, offsetBy: code.count / 2)

    return String(code[..<index]) + " " + String(code[index...])
  }
}
