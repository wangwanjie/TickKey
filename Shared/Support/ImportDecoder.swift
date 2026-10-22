import CoreImage
import Foundation
import ImageIO
import Vision

// MARK: - PhotoTokenDecoder

/// 在本机识别图片内全部二维码，单个无效二维码不阻断其余账户。
internal enum PhotoTokenDecoder {
  struct Result {
    var tokens: [Token] = []
    var rejectedCodes = 0
  }

  static func decode(_ data: Data) throws -> Result {
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    let payloads: [String?]
    do {
      try VNImageRequestHandler(data: data, options: [:]).perform([request])
      payloads = (request.results ?? []).map(\.payloadStringValue)
    } catch {
      // 部分系统环境无法初始化 Vision 推理上下文，回退到系统 Core Image 二维码检测。
      guard let image = CIImage(data: data),
            let detector = CIDetector(
              ofType: CIDetectorTypeQRCode,
              context: nil,
              options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
        throw error
      }
      let orientation = image.properties[kCGImagePropertyOrientation as String] as? Int ?? 1
      payloads = detector.features(in: image, options: [CIDetectorImageOrientation: orientation])
        .compactMap { $0 as? CIQRCodeFeature }
        .map(\.messageString)
    }
    var result = Result()
    for payload in payloads {
      if let payload, let tokens = try? (GoogleMigration.isMigration(payload)
        ? GoogleMigration.parse(payload).tokens : [OTPURI.parse(payload)]) {
        result.tokens.append(contentsOf: tokens)
      } else {
        result.rejectedCodes += 1
      }
    }
    return result
  }
}

// MARK: - ImportDecoder

/// 按内容识别文件和剪贴板中的账户，两端共用同一套格式判断，不依赖扩展名。
internal enum ImportDecoder {
  /// 文件解码结果；图片中无法识别的二维码只计数，不阻断其余账户。
  struct Result {
    var tokens: [Token] = []
    var rejectedCodes = 0
  }

  /// 加密备份需要密码；图片识别全部二维码；其余内容按逐行文本备份严格解析。
  static func decodeFile(_ data: Data, password: String? = nil) throws -> Result {
    guard !data.isEmpty, data.count <= BackupCodec.maximumSize else {
      throw TickKeyError.unsupportedFormat
    }

    if BackupCodec.isEncrypted(data) {
      return try Result(tokens: BackupCodec.decode(data, password: password))
    }

    if isImage(data) {
      let decoded = try PhotoTokenDecoder.decode(data)
      guard !decoded.tokens.isEmpty else {
        throw TickKeyError.noAccountsFound
      }
      return Result(tokens: decoded.tokens, rejectedCodes: decoded.rejectedCodes)
    }

    return try Result(tokens: BackupCodec.decode(data))
  }

  /// 剪贴板中包含 otpauth 链接时按文本解析，否则识别复制的二维码图片。
  static func decodePasteboard(text: String?, image: Data?) throws -> Result {
    if let text, text.range(of: "otpauth", options: .caseInsensitive) != nil {
      return try Result(tokens: BackupCodec.decode(Data(text.utf8)))
    }

    if let image {
      return try decodeFile(image)
    }

    throw TickKeyError.noAccountsFound
  }

  /// 仅凭文件头判断是否为系统可解码的图片，文本备份不会被误识别。
  static func isImage(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return false
    }
    return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
  }
}
