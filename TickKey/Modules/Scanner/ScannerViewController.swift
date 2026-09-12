import AVFoundation
import SnapKit
import UIKit

/// 管理相机授权与二维码识别，识别成功后返回表单供用户确认。
internal final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let pipeline = CameraSessionPipeline()
  private var preview: AVCaptureVideoPreviewLayer?
  private var previewConnection: AVCaptureConnection?
  private var previewOrientation: AVCaptureVideoOrientation?
  private var completed = false
  private var requestID = UUID()
  private var visible = false
  private let completion: (Token) -> Void

  init(completion: @escaping (Token) -> Void) {
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = Localization.text("scan")
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: Localization.text("cancel"),
      style: .plain,
      target: self,
      action: #selector(close))
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    visible = true
    let identifier = UUID()
    requestID = identifier
    PerformanceDiagnostics.event("camera.visible")

    // 页面出现后再请求授权，确保拒绝或无相机时的提示可以正常呈现。
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configure(identifier: identifier)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
        DispatchQueue.main
          .async {
            guard let self, self.visible, self.requestID == identifier else {
              return
            }
            if allowed {
              self.configure(identifier: identifier)
            } else {
              self.showMessage(Localization.text("camera.denied"))
            }
          }
      }
    default:
      showMessage(Localization.text("camera.denied"))
    }
  }

  /// 相机准备期间界面仍可取消；退出后到达的权限或配置回调不再启动相机。
  private func configure(identifier: UUID) {
    pipeline.prepare(delegate: self) { [weak self] result in
      guard let self, visible, requestID == identifier else {
        return
      }
      switch result {
      case let .success(session):
        attachPreview(session)
        pipeline.start()
      case .failure:
        showMessage(Localization.text("camera.unavailable"))
      }
    }
  }

  /// 图层与提示属于 UI，只在主线程安装；此时后台配置已完成且尚未启动采集。
  private func attachPreview(_ session: AVCaptureSession) {
    guard preview == nil else {
      return
    }
    preview = PerformanceDiagnostics.measure("camera.preview.attach") {
      let preview = AVCaptureVideoPreviewLayer(session: session)
      preview.videoGravity = .resizeAspectFill
      view.layer.insertSublayer(preview, at: 0)
      return preview
    }
    previewConnection = preview?.connection
    let help = UILabel()
    help.text = Localization.text("scan.help")
    help.numberOfLines = 0
    help.textAlignment = .center
    help.backgroundColor = .systemBackground
    help.layer.cornerRadius = 12
    help.clipsToBounds = true
    view.addSubview(help)
    help.snp.makeConstraints {
      $0.leading.trailing.equalToSuperview().inset(24)
      $0.bottom.equalTo(view.safeAreaLayoutGuide).inset(24)
      $0.height.greaterThanOrEqualTo(60)
    }
    view.setNeedsLayout()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds

    if let orientation = view.window?.windowScene?.interfaceOrientation {
      let video: AVCaptureVideoOrientation = switch orientation {
      case .landscapeLeft:
        .landscapeLeft
      case .landscapeRight:
        .landscapeRight
      case .portraitUpsideDown:
        .portraitUpsideDown
      default:
        .portrait
      }
      if let previewConnection, previewOrientation != video {
        previewOrientation = video
        pipeline.setOrientation(video, connection: previewConnection)
      }
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    visible = false
    requestID = UUID()
    pipeline.stop()
  }

  @objc private func close() {
    dismiss(animated: true)
  }

  /// 每次只处理一张二维码，防止连续回调重复弹出账户编辑页面。
  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection) {
    guard visible, !completed,
          let text = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else {
      return
    }
    // 立即关闭本次识别窗口，避免同一二维码在相邻帧重复触发。
    completed = true

    do {
      let token = try OTPURI.parse(text)
      dismiss(animated: true) { self.completion(token) }
    } catch {
      let alert = UIAlertController(
        title: Localization.text("error"),
        message: error.localizedDescription,
        preferredStyle: .alert)
      alert
        .addAction(UIAlertAction(title: Localization.text("continue"), style: .default) { [weak self] _ in
          self?.completed = false
        })
      present(alert, animated: true)
    }
  }
}
