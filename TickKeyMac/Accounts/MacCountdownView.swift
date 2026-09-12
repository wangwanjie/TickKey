import AppKit

/// 绘制从十二点方向开始收缩的倒计时扇形。
internal final class MacCountdownView: NSView {
  var fraction: Double = 1 {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    let accent = NSColor(named: "AccentColor") ?? .controlAccentColor
    accent.withAlphaComponent(0.13).setFill()
    NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    let path = NSBezierPath()
    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    path.move(to: center)
    path.appendArc(
      withCenter: center,
      radius: bounds.width / 2 - 1,
      startAngle: 90,
      endAngle: 90 - CGFloat(fraction) * 360,
      clockwise: true)
    path.close()
    accent.setFill()
    path.fill()
  }
}
