import UIKit
import AVFoundation
import SnapKit

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cn.vanjay.TickKey.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var completed = false
    private var requested = false
    private let completion: (Token) -> Void
    init(completion: @escaping (Token) -> Void) { self.completion = completion; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = L.text("scan"); view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: L.text("cancel"), style: .plain, target: self, action: #selector(close))
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !requested else { return }; requested = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async { if allowed { self?.configure() } else { self?.showMessage(L.text("camera.denied")) } }
            }
        default: showMessage(L.text("camera.denied"))
        }
    }
    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { showMessage(L.text("camera.unavailable")); return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { showMessage(L.text("camera.unavailable")); return }
        session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session); preview.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(preview, at: 0); self.preview = preview
        let help = UILabel(); help.text = L.text("scan.help"); help.numberOfLines = 0; help.textAlignment = .center
        help.backgroundColor = .systemBackground; help.layer.cornerRadius = 12; help.clipsToBounds = true
        view.addSubview(help); help.snp.makeConstraints { $0.leading.trailing.equalToSuperview().inset(24); $0.bottom.equalTo(view.safeAreaLayoutGuide).inset(24); $0.height.greaterThanOrEqualTo(60) }
        view.setNeedsLayout()
        let session = session
        queue.async { session.startRunning() }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); preview?.frame = view.bounds
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            let video: AVCaptureVideoOrientation
            switch orientation { case .landscapeLeft: video = .landscapeLeft; case .landscapeRight: video = .landscapeRight; case .portraitUpsideDown: video = .portraitUpsideDown; default: video = .portrait }
            preview?.connection?.videoOrientation = video
        }
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); let session = session; queue.async { session.stopRunning() } }
    @objc private func close() { dismiss(animated: true) }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !completed, let text = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        completed = true
        do {
            let token = try OTPURI.parse(text)
            dismiss(animated: true) { self.completion(token) }
        } catch {
            let alert = UIAlertController(title: L.text("error"), message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L.text("continue"), style: .default) { [weak self] _ in self?.completed = false })
            present(alert, animated: true)
        }
    }
}
