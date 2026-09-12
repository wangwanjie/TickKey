import UIKit
import Combine

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var observation: AnyCancellable?
    private var privacyCover: UIView?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UINavigationController(rootViewController: AccountsViewController())
        window.tintColor = UIColor(named: "AccentColor")
        self.window = window
        observation = AppModel.shared.$preferences.sink { [weak window] value in
            window?.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: value.appearance) ?? .unspecified
        }
        window.makeKeyAndVisible()
    }
    func sceneWillResignActive(_ scene: UIScene) {
        guard let window else { return }
        let cover = UIView(frame: window.bounds)
        cover.backgroundColor = .systemBackground
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let label = UILabel(frame: cover.bounds)
        label.text = "TickKey"; label.font = .systemFont(ofSize: 30, weight: .bold)
        label.textAlignment = .center; label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.addSubview(label); window.addSubview(cover); privacyCover = cover
    }
    func sceneDidBecomeActive(_ scene: UIScene) { privacyCover?.removeFromSuperview(); privacyCover = nil }
}
