import XCTest
import CoreImage
@testable import TickKey

final class TickKeyTests: XCTestCase {
    func testQRCodeCanBeDecoded() throws {
        let token = try Token(issuer: "TickKey", account: "test@example.com", secret: "JBSWY3DPEHPK3PXP")
        let image = CIImage(cgImage: try QRCode.image(for: token))
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        let features = detector.features(in: image).compactMap { $0 as? CIQRCodeFeature }
        XCTAssertEqual(features.first?.messageString, OTPURI.encode(token))
    }
}
