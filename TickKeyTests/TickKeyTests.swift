import CoreImage
@testable import TickKey
import UIKit
import XCTest

/// 从生成的二维码中还原 URI，验证实际图像能被系统识别。
internal final class TickKeyTests: XCTestCase {
  /// 真实加载导出页面并等待后台二维码，覆盖共同父视图崩溃和快速翻页过期结果。
  @MainActor
  func testQRExportLayoutAndPagination() async throws {
    let first = try Token(issuer: "Example", account: "first", secret: "JBSWY3DPEHPK3PXP")
    let second = try Token(issuer: "Example", account: "second", secret: "GEZDGNBVGY3TQOJQ")
    let controller = QRViewController(tokens: [first, second])
    controller.loadViewIfNeeded()
    controller.beginAppearanceTransition(true, animated: false)
    controller.endAppearanceTransition()
    let image = try XCTUnwrap(descendants(of: controller.view)
      .compactMap { $0 as? UIImageView }
      .first { $0.accessibilityIdentifier == "export-qr-image" })
    let buttons = descendants(of: controller.view).compactMap { $0 as? UIButton }
    let next = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "next-qr" })
    let previous = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "previous-qr" })
    XCTAssertFalse(previous.isEnabled)
    next.sendActions(for: .touchUpInside)
    previous.sendActions(for: .touchUpInside)
    next.sendActions(for: .touchUpInside)
    XCTAssertFalse(next.isEnabled)
    let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in image.image != nil }, object: nil)
    await fulfillment(of: [rendered], timeout: 10)
    let cgImage = try XCTUnwrap(image.image?.cgImage)
    XCTAssertEqual(try PhotoTokenDecoder.decode(makePhoto([cgImage])).tokens.first?.account, second.account)
    for size in [CGSize(width: 320, height: 568), CGSize(width: 844, height: 390)] {
      controller.view.frame = CGRect(origin: .zero, size: size)
      controller.view.setNeedsLayout()
      controller.view.layoutIfNeeded()
      XCTAssertGreaterThan(image.bounds.width, 0)
      XCTAssertLessThanOrEqual(image.bounds.width, min(360, size.width - 48))
      XCTAssertEqual(image.bounds.width, image.bounds.height, accuracy: 0.5)
      XCTAssertFalse(image.hasAmbiguousLayout)
    }
  }

  @MainActor
  private func descendants(of view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
  }

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
