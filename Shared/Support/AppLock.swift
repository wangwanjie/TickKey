import Combine
import Foundation
import LocalAuthentication

// MARK: - AppLock

/// 管理可选的启动解锁：开启后启动、回到前台或锁屏后需要通过系统身份验证才能查看验证码。
/// 身份验证由系统完成，应用不保存生物特征或设备密码。
@MainActor
internal final class AppLock: ObservableObject {
  static let shared = AppLock()
  @Published private(set) var isLocked: Bool
  private var authenticating = false
  /// 只在启动或重新上锁后自动弹出一次验证，避免取消后因前台切换反复弹窗。
  private var promptPending: Bool

  private init() {
    let required = AppModel.shared.preferences.requiresUnlock
    isLocked = required
    promptPending = required
  }

  /// 进入后台、锁屏或用户手动上锁时调用；未开启功能时不做任何事。
  func lock() {
    guard AppModel.shared.preferences.requiresUnlock else {
      return
    }
    isLocked = true
    promptPending = true
  }

  /// 自动触发只消费一次待处理请求；用户点击解锁按钮时始终尝试。
  func unlock(automatic: Bool = false, failure: ((Error) -> Void)? = nil) {
    guard isLocked, !authenticating else {
      return
    }
    if automatic {
      guard promptPending else {
        return
      }
    }
    promptPending = false
    authenticating = true
    Self.authenticate(reason: Localization.text("lock.reason")) { [weak self] result in
      guard let self else {
        return
      }
      authenticating = false
      switch result {
      case .success:
        isLocked = false
      case let .failure(error):
        if !Self.isCancellation(error) {
          failure?(error)
        }
      }
    }
  }

  /// 开启或关闭前都先验证一次，确认设备可用且由本人操作，成功后才写入偏好。
  func setRequiresUnlock(_ enabled: Bool, completion: @escaping (Error?) -> Void) {
    Self.authenticate(reason: Localization.text(enabled ? "lock.enable.reason" : "lock.disable.reason")) { result in
      do {
        try result.get()
        var value = AppModel.shared.preferences
        value.requiresUnlock = enabled
        try AppModel.shared.setPreferences(value)
        completion(nil)
      } catch {
        completion(Self.isCancellation(error) ? nil : error)
      }
    }
  }

  /// 使用设备所有者策略：优先生物识别，失败或不可用时允许输入设备密码。
  private static func authenticate(reason: String, completion: @escaping (Result<Void, Error>) -> Void) {
    let context = LAContext()
    var error: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      completion(.failure(TickKeyError.authenticationUnavailable))
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
      DispatchQueue.main.async {
        if success {
          completion(.success(()))
        } else {
          completion(.failure(error ?? TickKeyError.authenticationUnavailable))
        }
      }
    }
  }

  /// 用户或系统取消属于正常操作，不弹出错误提示。
  private static func isCancellation(_ error: Error) -> Bool {
    guard let error = error as? LAError else {
      return false
    }
    return [.userCancel, .systemCancel, .appCancel].contains(error.code)
  }
}
