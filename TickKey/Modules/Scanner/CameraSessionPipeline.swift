import AVFoundation
import Foundation

/// 所有会话状态只在专用队列访问；包括设备枚举、输入创建、配置、启动和停止。
internal final class CameraSessionPipeline {
  private enum Failure: Error {
    case unavailable
  }

  private let queue = DispatchQueue(label: "cn.vanjay.TickKey.camera", qos: .userInitiated)
  private var session: AVCaptureSession?

  /// 后台准备会话，主线程仅绑定预览图层；预览绑定完毕后调用 start。
  func prepare(
    delegate: AVCaptureMetadataOutputObjectsDelegate,
    completion: @escaping (Result<AVCaptureSession, Error>) -> Void) {
    queue.async {
      let result = Result {
        try PerformanceDiagnostics.measure("camera.configure") {
          if let session = self.session {
            return session
          }
          let session = try Self.makeSession(delegate: delegate)
          self.session = session
          return session
        }
      }
      DispatchQueue.main.async { completion(result) }
    }
  }

  private static func makeSession(delegate: AVCaptureMetadataOutputObjectsDelegate) throws -> AVCaptureSession {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let session = AVCaptureSession()
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    guard let device = AVCaptureDevice.default(for: .video) else {
      throw Failure.unavailable
    }
    let input = try PerformanceDiagnostics.measure("camera.input.create") { try AVCaptureDeviceInput(device: device) }
    guard session.canAddInput(input) else {
      throw Failure.unavailable
    }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      throw Failure.unavailable
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(delegate, queue: .main)
    guard output.availableMetadataObjectTypes.contains(.qr) else {
      throw Failure.unavailable
    }
    output.metadataObjectTypes = [.qr]
    return session
  }

  func start() {
    queue.async {
      PerformanceDiagnostics.measure("camera.start") { self.session?.startRunning() }
    }
  }

  func stop() {
    queue.async {
      PerformanceDiagnostics.measure("camera.stop") { self.session?.stopRunning() }
    }
  }

  /// 方向修改也走会话队列，避免主线程在 startRunning 持有连接锁时同步等待。
  func setOrientation(_ orientation: AVCaptureVideoOrientation, connection: AVCaptureConnection) {
    queue.async {
      if connection.isVideoOrientationSupported {
        connection.videoOrientation = orientation
      }
    }
  }
}
