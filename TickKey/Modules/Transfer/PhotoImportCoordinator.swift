import CoreImage
import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import Vision

// MARK: - PhotoTokenDecoder

/// 在本机识别图片内全部二维码，单个无效二维码不阻断其余账户。
internal enum PhotoTokenDecoder {
  struct Result {
    var tokens: [Token] = []
    var rejectedCodes = 0
  }

  static func decode(_ data: Data) throws -> Result {
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    let payloads: [String?]
    do {
      try VNImageRequestHandler(data: data, options: [:]).perform([request])
      payloads = (request.results ?? []).map(\.payloadStringValue)
    } catch {
      // 部分系统环境无法初始化 Vision 推理上下文，回退到系统 Core Image 二维码检测。
      guard let image = CIImage(data: data),
            let detector = CIDetector(
              ofType: CIDetectorTypeQRCode,
              context: nil,
              options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
        throw error
      }
      let orientation = image.properties[kCGImagePropertyOrientation as String] as? Int ?? 1
      payloads = detector.features(in: image, options: [CIDetectorImageOrientation: orientation])
        .compactMap { $0 as? CIQRCodeFeature }
        .map(\.messageString)
    }
    var result = Result()
    for payload in payloads {
      if let payload, let token = try? OTPURI.parse(payload) {
        result.tokens.append(token)
      } else {
        result.rejectedCodes += 1
      }
    }
    return result
  }
}

// MARK: - PhotoImportCoordinator

/// 系统照片选择器仅授权选中的图片，逐张后台识别以限制批量导入内存占用。
@MainActor
internal final class PhotoImportCoordinator: NSObject, PHPickerViewControllerDelegate {
  private weak var presenter: UIViewController?
  private var tokens: [Token] = []
  private var failedImages = 0
  private var rejectedCodes = 0
  private var selections: [PHPickerResult] = []

  init(presenter: UIViewController) {
    self.presenter = presenter
  }

  func choosePhotos() {
    var configuration = PHPickerConfiguration()
    configuration.filter = .images
    configuration.selectionLimit = 0
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    presenter?.present(picker, animated: true)
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true) { [weak self] in
      guard let self, !results.isEmpty else {
        return
      }
      tokens = []
      failedImages = 0
      rejectedCodes = 0
      selections = results
      let progress = UIAlertController(title: Localization.text("processing"), message: nil, preferredStyle: .alert)
      presenter?.present(progress, animated: true) {
        self.load(at: 0, progress: progress)
      }
    }
  }

  /// 顺序读取原始图像数据，Vision 自动处理照片方向；不保存图片或记录密钥。
  private func load(at index: Int, progress: UIAlertController) {
    guard index < selections.count else {
      progress.dismiss(animated: true) { [weak self] in self?.finish() }
      return
    }
    progress.message = String(format: Localization.text("import.photos.progress"), index + 1, selections.count)
    selections[index]
      .itemProvider
      .loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
        DispatchQueue.global(qos: .userInitiated).async {
          let decoded = autoreleasepool { data.flatMap { try? PhotoTokenDecoder.decode($0) } }
          DispatchQueue.main.async {
            guard let self else {
              return
            }
            if let decoded {
              self.tokens.append(contentsOf: decoded.tokens)
              self.rejectedCodes += decoded.rejectedCodes
              if decoded.tokens.isEmpty {
                self.failedImages += 1
              }
            } else {
              self.failedImages += 1
            }
            self.load(at: index + 1, progress: progress)
          }
        }
      }
  }

  /// 汇总有效账户后一次事务去重写入，部分失败时仍反馈成功数量及跳过原因。
  private func finish() {
    defer {
      tokens = []
      selections = []
    }
    do {
      var message = tokens.isEmpty
        ? Localization.text("import.photos.empty")
        : try AppModel.shared.importTokens(tokens)
      if failedImages > 0 || rejectedCodes > 0 {
        message += "\n\n" + String(
          format: Localization.text("import.photos.skipped"), failedImages, rejectedCodes)
      }
      presenter?.showMessage(message)
    } catch {
      presenter?.showError(error)
    }
  }
}
