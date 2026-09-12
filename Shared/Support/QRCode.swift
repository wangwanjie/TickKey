import Foundation
import CoreImage

enum QRCode {
    /// 使用整数缩放并留出四模块静区，避免插值影响扫码。
    static func image(for token: Token) throws -> CGImage {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw TickKeyError.invalidURI }
        filter.setValue(Data(OTPURI.encode(token).utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { throw TickKeyError.invalidURI }
        let extent = output.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        let result = output.composited(over: white).transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let image = CIContext().createCGImage(result, from: result.extent) else { throw TickKeyError.invalidURI }
        return image
    }
}
