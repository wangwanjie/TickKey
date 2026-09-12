import CoreImage
@testable import TickKey
import XCTest

/// 从生成的二维码中还原 URI，验证实际图像能被系统识别。
internal final class TickKeyTests: XCTestCase {
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
