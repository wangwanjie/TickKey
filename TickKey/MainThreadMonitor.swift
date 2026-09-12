import Combine
import Foundation
import UIKit

/// 后台队列检查主队列心跳；只在前台启用，不阻塞主线程，不采集业务数据。
internal final class MainThreadMonitor {
  static let shared = MainThreadMonitor()
  private let queue = DispatchQueue(label: "cn.vanjay.TickKey.heartbeat", qos: .utility)
  private var timer: DispatchSourceTimer?
  private var subscriptions = Set<AnyCancellable>()
  private var active = false
  private var pending: UUID?
  private var sentAt: TimeInterval = 0
  private var reported = false
  private var lastCheckAt: TimeInterval?

  func start() {
    #if DEBUG
      guard timer == nil else {
        return
      }
      for (name, active) in [
        (UIApplication.didBecomeActiveNotification, true),
        (UIApplication.willResignActiveNotification, false)
      ] {
        NotificationCenter.default
          .publisher(for: name)
          .sink { [weak self] _ in
            self?.queue.async { [weak self] in
              self?.active = active
              self?.pending = nil
              self?.lastCheckAt = nil
            }
          }
          .store(in: &subscriptions)
      }
      observeKeyboard()
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now(), repeating: .milliseconds(100))
      timer.setEventHandler { [weak self] in self?.check() }
      self.timer = timer
      timer.resume()
    #endif
  }

  /// 记录键盘转场边界，不读取键盘内容或输入文本。
  private func observeKeyboard() {
    let events: [(Notification.Name, StaticString)] = [
      (UIResponder.keyboardWillShowNotification, "keyboard.willShow"),
      (UIResponder.keyboardDidShowNotification, "keyboard.didShow"),
      (UIResponder.keyboardWillHideNotification, "keyboard.willHide"),
      (UIResponder.keyboardDidHideNotification, "keyboard.didHide")
    ]
    for (name, event) in events {
      NotificationCenter.default
        .publisher(for: name)
        .sink { _ in PerformanceDiagnostics.event(event) }
        .store(in: &subscriptions)
    }
  }

  /// 同时只保留一次心跳；停顿期间输出一次告警，恢复后输出完整延迟。
  private func check() {
    guard active else {
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    let monitorGap = lastCheckAt.map { now - $0 } ?? 0
    lastCheckAt = now
    if pending != nil {
      let delay = now - sentAt
      if delay >= 0.75, !reported {
        reported = true
        reportStall(delay, monitorGap: monitorGap)
      }
      return
    }
    let identifier = UUID()
    pending = identifier
    sentAt = ProcessInfo.processInfo.systemUptime
    reported = false
    DispatchQueue.main.async {
      let receivedAt = ProcessInfo.processInfo.systemUptime
      self.queue.async {
        guard self.pending == identifier else {
          return
        }
        if self.reported {
          let milliseconds = Int((receivedAt - self.sentAt) * 1000)
          PerformanceDiagnostics.logger.notice("[TickKeyPerf] main-thread-recovered ms=\(milliseconds)")
        }
        self.pending = nil
      }
    }
  }

  /// 独立且不内联的断点入口，供 LLDB 在停顿发生时采集其他线程，而不是恢复后的调用栈。
  @inline(never)
  private func reportStall(_ delay: TimeInterval, monitorGap: TimeInterval) {
    let milliseconds = Int(delay * 1000)
    let gap = Int(monitorGap * 1000)
    PerformanceDiagnostics.logger.warning("[TickKeyPerf] main-thread-stall ms=\(milliseconds) monitor-gap-ms=\(gap)")
  }
}
