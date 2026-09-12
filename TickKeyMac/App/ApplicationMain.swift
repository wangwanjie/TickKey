import AppKit
import Combine

// MARK: - ApplicationMain

/// 原生 macOS 入口，显式保留应用代理直到事件循环结束。
@main
internal enum ApplicationMain {
  /// 由 Swift 根据 @main 生成的系统入口调用，源码中无需手动调用此方法。
  static func main() {
    let app = NSApplication.shared
    let delegate = MacAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
  }
}

// MARK: - MacAppDelegate

/// 创建主窗口、自定义菜单和偏好设置窗口，统一响应外观切换。
@MainActor
internal final class MacAppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  private var preferences: PreferencesWindowController?
  private var observation: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = "TickKey"
    window.minSize = NSSize(width: 640, height: 460)
    window.contentViewController = MacAccountsViewController()
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    observation = AppModel.shared.$preferences.sink { [weak self] value in
      NSApp.appearance = value.appearance == 0 ? nil : NSAppearance(named: value.appearance == 1 ? .aqua : .darkAqua)
      self?.buildMenu()
    }
    UpdateController.shared.start()
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    window?.makeKeyAndOrderFront(nil)

    return true
  }

  @objc func showPreferences() {
    if preferences == nil {
      preferences = PreferencesWindowController()
    }
    preferences?.showWindow(nil)
    preferences?.window?.makeKeyAndOrderFront(nil)
  }

  /// 提供应用功能及标准文本编辑快捷键，使所有输入框支持复制和粘贴。
  private func buildMenu() {
    let menu = NSMenu()
    func submenu(_ title: String) -> NSMenu {
      let item = NSMenuItem()
      item.title = title
      let child = NSMenu(title: title)
      item.submenu = child
      menu.addItem(item)

      return child
    }
    func add(_ title: String, _ action: Selector, _ key: String, to menu: NSMenu, target: AnyObject? = nil) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.target = target
      menu.addItem(item)
    }

    let app = submenu("TickKey")
    add(Localization.text("settings") + "…", #selector(showPreferences), ",", to: app, target: self)
    add(
      Localization.text("check.updates") + "…",
      #selector(UpdateController.check),
      "",
      to: app,
      target: UpdateController.shared)
    app.addItem(.separator())
    add(Localization.text("quit"), #selector(NSApplication.terminate(_:)), "q", to: app)
    let file = submenu(Localization.text("file"))
    add(Localization.text("add"), #selector(MacAccountsViewController.addAccount), "n", to: file)
    add(Localization.text("import"), #selector(MacAccountsViewController.importAccounts), "o", to: file)
    add(Localization.text("export"), #selector(MacAccountsViewController.exportAccounts), "e", to: file)
    let edit = submenu(Localization.text("edit"))
    add(Localization.text("undo"), Selector(("undo:")), "z", to: edit)
    add(Localization.text("redo"), Selector(("redo:")), "Z", to: edit)
    add(Localization.text("cut"), #selector(NSText.cut(_:)), "x", to: edit)
    add(Localization.text("copy"), #selector(NSText.copy(_:)), "c", to: edit)
    add(Localization.text("paste"), #selector(NSText.paste(_:)), "v", to: edit)
    add(Localization.text("select.all"), #selector(NSText.selectAll(_:)), "a", to: edit)
    let windows = submenu(Localization.text("window"))
    add(Localization.text("minimize"), #selector(NSWindow.miniaturize(_:)), "m", to: windows)
    NSApp.windowsMenu = windows
    NSApp.mainMenu = menu
  }
}
