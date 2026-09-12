import Foundation

enum L {
    static var language = "system"
    static func text(_ key: String) -> String {
        let code = language == "system" ? (Bundle.preferredLocalizations(from: ["en", "zh-Hans", "zh-Hant"]).first ?? "en") : language
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

enum AppInfo {
    static var version: String {
        "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))"
    }
    static var issuesURL: URL? {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "TickKeyRepositoryURL") as? String,
              let url = URL(string: string), url.scheme == "https", url.host == "github.com",
              url.pathComponents.count >= 3 else { return nil }
        return url.appendingPathComponent("issues")
    }
}
