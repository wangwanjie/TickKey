import Foundation
import OSLog

/// 调试日志只接受静态阶段名和数量，不记录账户、文件路径、密码或二维码内容。
internal enum PerformanceDiagnostics {
  static let logger = Logger(subsystem: "cn.vanjay.TickKey", category: "Performance")

  static func event(_ name: StaticString, count: Int = 0) {
    #if DEBUG
      logger.notice("[TickKeyPerf] \(name.description, privacy: .public) count=\(count) main=\(Thread.isMainThread)")
    #endif
  }

  /// 开始和结束使用同一编号；即使抛错，也能看到该阶段是否完成及其耗时。
  static func measure<T>(_ name: StaticString, count: Int = 0, _ operation: () throws -> T) rethrows -> T {
    #if DEBUG
      let identifier = UUID().uuidString
      let start = ProcessInfo.processInfo.systemUptime
      logger
        .notice(
          """
          [TickKeyPerf] begin \(name.description, privacy: .public) id=\(identifier, privacy: .public) \
          count=\(count) main=\(Thread.isMainThread)
          """)
      defer {
        let milliseconds = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
        logger
          .notice(
            """
            [TickKeyPerf] end \(name.description, privacy: .public) \
            id=\(identifier, privacy: .public) ms=\(milliseconds)
            """)
      }
    #endif
    return try operation()
  }
}
