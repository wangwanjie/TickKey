import UIKit

/// 根据剩余比例绘制扇形，绘制进度与系统时间保持同步。
internal final class CountdownView: UIView {
  var fraction: Double = 1 {
    didSet { setNeedsDisplay() }
  }

  override func draw(_ rect: CGRect) {
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let radius = min(bounds.width, bounds.height) / 2 - 2
    let background = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
    tintColor.withAlphaComponent(0.13).setFill()
    background.fill()
    let path = UIBezierPath()
    path.move(to: center)
    path.addArc(
      withCenter: center,
      radius: radius,
      startAngle: -.pi / 2,
      endAngle: -.pi / 2 + .pi * 2 * fraction,
      clockwise: true)
    path.close()
    tintColor.setFill()
    path.fill()
  }
}
