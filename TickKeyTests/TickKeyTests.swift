import CoreImage
@testable import TickKey
import UIKit
import XCTest

/// 从生成的二维码中还原 URI，验证实际图像能被系统识别。
internal final class TickKeyTests: XCTestCase {
  /// 真实拼图包含多个账户与无关二维码，验证部分无效时继续识别。
  func testPhotoImportFindsMultipleAccountsAndSkipsUnsupportedCode() throws {
    let first = try Token(issuer: "Example", account: "first", secret: "JBSWY3DPEHPK3PXP")
    let second = try Token(issuer: "Example", account: "second", secret: "GEZDGNBVGY3TQOJQ")
    let unsupported = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
    unsupported.setValue(Data("https://example.com".utf8), forKey: "inputMessage")
    let output = try XCTUnwrap(unsupported.outputImage)
    let invalidImage = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
    let data = try makePhoto([QRCode.image(for: first), QRCode.image(for: second), invalidImage])
    let result = try PhotoTokenDecoder.decode(data)
    XCTAssertEqual(Set(result.tokens.map(\.account)), ["first", "second"])
    XCTAssertEqual(result.rejectedCodes, 1)
  }

  func testPhotoImportReadsRotatedQRCode() throws {
    let token = try Token(issuer: "Example", account: "rotated", secret: "JBSWY3DPEHPK3PXP")
    let original = try UIImage(cgImage: QRCode.image(for: token), scale: 1, orientation: .right)
    let renderer = UIGraphicsImageRenderer(size: original.size)
    let data = renderer.pngData { _ in original.draw(at: .zero) }
    XCTAssertEqual(try PhotoTokenDecoder.decode(data).tokens.first?.account, "rotated")
  }

  func testPhotoImportHandlesBlankAndCorruptImages() throws {
    XCTAssertTrue(try PhotoTokenDecoder.decode(makePhoto([])).tokens.isEmpty)
    XCTAssertThrowsError(try PhotoTokenDecoder.decode(Data("invalid image".utf8)))
  }

  /// 用白色背景及独立静区构造可供 Vision 识别的截图，不使用真实账户。
  private func makePhoto(_ images: [CGImage]) -> Data {
    let size = CGSize(width: max(1, images.count) * 400, height: 400)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      context.cgContext.interpolationQuality = .none
      for (index, image) in images.enumerated() {
        UIImage(cgImage: image).draw(in: CGRect(x: index * 400 + 30, y: 30, width: 340, height: 340))
      }
    }
  }

  func testQRCodeCanBeDecoded() throws {
    let token = try Token(issuer: "TickKey", account: "test@example.com", secret: "JBSWY3DPEHPK3PXP")
    let image = try CIImage(cgImage: QRCode.image(for: token))
    let detector = try XCTUnwrap(CIDetector(
      ofType: CIDetectorTypeQRCode,
      context: nil,
      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
    let features = detector.features(in: image).compactMap { $0 as? CIQRCodeFeature }
    XCTAssertEqual(features.first?.messageString, try OTPURI.encode(token))
  }
}
