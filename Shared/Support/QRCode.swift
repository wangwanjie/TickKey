import CoreImage
import Foundation

/// 使用系统 Core Image 生成账户二维码，二维码内容仅在本机处理。
internal enum QRCode {
  /// 二维码是小幅静态位图，使用可复用的软件渲染上下文，避开首次 Metal/GPU 初始化。
  private static let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
  /// 使用整数缩放并留出四模块静区，避免插值影响扫码。
  static func image(for token: Token) throws -> CGImage {
    try image(for: OTPURI.encode(token))
  }

  static func image(for payload: String) throws -> CGImage {
    guard let filter = PerformanceDiagnostics.measure("qr.filter.create", {
      CIFilter(name: "CIQRCodeGenerator")
    }) else {
      throw TickKeyError.invalidURI
    }
    filter.setValue(Data(payload.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")

    guard let output = PerformanceDiagnostics.measure("qr.filter.output", { filter.outputImage }) else {
      throw TickKeyError.invalidURI
    }

    // 静区保持纯白，不受系统深色模式影响。
    let extent = output.extent.insetBy(dx: -4, dy: -4)
    let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
    let result = output.composited(over: white).transformed(by: CGAffineTransform(scaleX: 6, y: 6))

    guard let image = PerformanceDiagnostics.measure("qr.bitmap.render", {
      // 显式立即生成像素，避免 UIImageView 首次显示时才触发延迟渲染。
      context.createCGImage(
        result,
        from: result.extent,
        format: .RGBA8,
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        deferred: false)
    }) else {
      throw TickKeyError.invalidURI
    }

    return image
  }
}
