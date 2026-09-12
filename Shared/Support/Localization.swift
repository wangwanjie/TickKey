import Foundation

// MARK: - Localization

/// 统一解析当前语言的资源包，为两端界面和业务错误提供相同文案。
internal enum Localization {
  static var language = "system"

  /// 跟随系统时只在已提供的语言中选择，找不到资源时使用主资源包回退。
  static func text(_ key: String) -> String {
    let code = language == "system" ? (
      Bundle.preferredLocalizations(from: ["en", "zh-Hans", "zh-Hant"]).first ?? "en") :
      language
    let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    return bundle.localizedString(forKey: key, value: key, table: "Localizable")
  }
}

// MARK: - AppInfo

/// 从已构建应用的 Info.plist 读取版本和公开仓库配置。
internal enum AppInfo {
  static var version: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"

    return "\(version) (\(build))"
  }

  static var issuesURL: URL? {
    guard let string = Bundle.main.object(forInfoDictionaryKey: "TickKeyRepositoryURL") as? String,
          let url = URL(string: string), url.scheme == "https", url.host == "github.com",
          url.pathComponents.count >= 3 else {
      return nil
    }

    return url.appendingPathComponent("issues")
  }
}
