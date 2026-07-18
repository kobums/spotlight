import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var loginMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = PanelController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Spot")
        }
        let menu = NSMenu()
        menu.delegate = self
        let showItem = NSMenuItem(title: "Spot 열기 (⌥Space)", action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())
        loginMenuItem = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu

        HotKeyManager.shared.handler = { [weak self] in
            self?.panelController.toggle()
        }
        HotKeyManager.shared.register()

        ClipboardStore.shared.startMonitoring()
        LoginItemManager.ensureRegisteredOnFirstLaunch()
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginMenuItem.state = LoginItemManager.isEnabled ? .on : .off
    }

    @objc private func togglePanel() {
        panelController.toggle()
    }

    @objc private func toggleLoginItem() {
        LoginItemManager.toggle()
    }
}
