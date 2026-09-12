import AppKit

// 原生绘制矢量轮廓，生成 iOS 与 macOS 共用的图标素材。
private let root = URL(fileURLWithPath: CommandLine.arguments[1])
private let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(srgbRed: 0.12, green: 0.28, blue: 0.61, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 220, yRadius: 220).fill()
private let ring = NSBezierPath(ovalIn: NSRect(x: 220, y: 235, width: 584, height: 584))
ring.lineWidth = 58
NSColor.white.withAlphaComponent(0.94).setStroke()
ring.stroke()
private let pie = NSBezierPath()
pie.move(to: NSPoint(x: 512, y: 527))
pie.appendArc(withCenter: NSPoint(x: 512, y: 527), radius: 220, startAngle: 90, endAngle: 0, clockwise: true)
pie.close()
NSColor(srgbRed: 0.49, green: 0.78, blue: 0.98, alpha: 1).setFill()
pie.fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 479, y: 384, width: 66, height: 203), xRadius: 24, yRadius: 24).fill()
NSBezierPath(ovalIn: NSRect(x: 432, y: 510, width: 160, height: 160)).fill()
NSColor(srgbRed: 0.12, green: 0.28, blue: 0.61, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 482, y: 561, width: 60, height: 60)).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 435, y: 853, width: 154, height: 45), xRadius: 20, yRadius: 20).fill()
image.unlockFocus()

/// 根据平台选择透明度，iOS 图标必须不含 alpha 通道，渲染失败时中止生成。
private func png(_ size: Int, to url: URL) throws {
  if url.path.contains("/TickKey/Assets") {
    // AppKit 无法可靠绘制三通道位图；先用不透明的四字节 RGB 上下文绘制，再编码 PNG。
    guard let context = CGContext(
      data: nil,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: size * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    context.setFillColor(CGColor(srgbRed: 0.12, green: 0.28, blue: 0.61, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let rendered = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
    return
  }

  guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0) else {
    throw CocoaError(.fileWriteUnknown)
  }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
  NSGraphicsContext.restoreGraphicsState()
  guard let data = rep.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  try data.write(to: url)
}

private let mac = root.appendingPathComponent("TickKeyMac/Resources/Assets.xcassets/AppIcon.appiconset")
private let ios = root.appendingPathComponent("TickKey/Assets.xcassets/AppIcon.appiconset")
for folder in [mac, ios] {
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
}

private var entries: [[String: String]] = []
for size in CommandLine.arguments.contains("--ios-only") ? [] : [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let name = "icon-\(size)@\(scale)x.png"
    try png(size * scale, to: mac.appendingPathComponent(name))
    entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
  }
}

if !entries.isEmpty {
  try JSONSerialization.data(
    withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]],
    options: [.prettyPrinted])
    .write(to: mac.appendingPathComponent("Contents.json"))
}

entries = []
for (idiom, sizes, scales) in [("iphone", [20.0, 29, 40, 60], [2, 3]), ("ipad", [20.0, 29, 40, 76, 83.5], [1, 2])] {
  for size in sizes {
    for scale in scales {
      if size == 83.5, scale == 1 {
        continue
      }

      let name = "\(idiom)-\(size)@\(scale)x.png"
      try png(Int(size * Double(scale)), to: ios.appendingPathComponent(name))
      entries.append(["idiom": idiom, "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
  }
}

try png(1024, to: ios.appendingPathComponent("marketing.png"))
entries.append(["idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "marketing.png"])
try JSONSerialization.data(
  withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]],
  options: [.prettyPrinted])
  .write(to: ios.appendingPathComponent("Contents.json"))
