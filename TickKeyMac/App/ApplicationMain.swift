import AppKit
import Combine

@main
enum ApplicationMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MacAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var preferences: PreferencesWindowController?
    private var observation: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "TickKey"; window.minSize = NSSize(width: 640, height: 460)
        window.contentViewController = MacAccountsViewController()
        window.isReleasedWhenClosed = false; window.center(); window.makeKeyAndOrderFront(nil)
        observation = AppModel.shared.$preferences.sink { [weak self] value in
            NSApp.appearance = value.appearance == 0 ? nil : NSAppearance(named: value.appearance == 1 ? .aqua : .darkAqua)
            self?.buildMenu()
        }
        UpdateController.shared.start()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }
    @objc func showPreferences() {
        if preferences == nil { preferences = PreferencesWindowController() }
        preferences?.showWindow(nil); preferences?.window?.makeKeyAndOrderFront(nil)
    }
    private func buildMenu() {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title; let child = NSMenu(title: title); item.submenu = child; menu.addItem(item); return child
        }
        func add(_ title: String, _ action: Selector, _ key: String, to menu: NSMenu, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = target; menu.addItem(item)
        }
        let app = submenu("TickKey")
        add(L.text("settings") + "…", #selector(showPreferences), ",", to: app, target: self)
        add(L.text("check.updates") + "…", #selector(UpdateController.check), "", to: app, target: UpdateController.shared)
        app.addItem(.separator()); add(L.text("quit"), #selector(NSApplication.terminate(_:)), "q", to: app)
        let file = submenu(L.text("file"))
        add(L.text("add"), #selector(MacAccountsViewController.addAccount), "n", to: file)
        add(L.text("import"), #selector(MacAccountsViewController.importAccounts), "o", to: file)
        add(L.text("export"), #selector(MacAccountsViewController.exportAccounts), "e", to: file)
        let edit = submenu(L.text("edit"))
        add(L.text("undo"), Selector(("undo:")), "z", to: edit)
        add(L.text("redo"), Selector(("redo:")), "Z", to: edit)
        add(L.text("cut"), #selector(NSText.cut(_:)), "x", to: edit)
        add(L.text("copy"), #selector(NSText.copy(_:)), "c", to: edit)
        add(L.text("paste"), #selector(NSText.paste(_:)), "v", to: edit)
        add(L.text("select.all"), #selector(NSText.selectAll(_:)), "a", to: edit)
        let windows = submenu(L.text("window")); add(L.text("minimize"), #selector(NSWindow.miniaturize(_:)), "m", to: windows)
        NSApp.windowsMenu = windows; NSApp.mainMenu = menu
    }
}
