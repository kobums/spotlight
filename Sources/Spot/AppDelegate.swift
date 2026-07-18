import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var hintModeController: HintModeController!
    private var loginMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = PanelController()
        hintModeController = HintModeController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Spot")
        }
        let menu = NSMenu()
        menu.delegate = self
        let showItem = NSMenuItem(title: "Spot 열기 (⌥Space)", action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        let hintItem = NSMenuItem(title: "힌트 모드 (⌃Space)", action: #selector(toggleHintMode), keyEquivalent: "")
        hintItem.target = self
        menu.addItem(hintItem)
        menu.addItem(.separator())
        loginMenuItem = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu

        HotKeyManager.shared.register(.launcher, keyCode: kVK_Space, modifiers: optionKey) { [weak self] in
            self?.panelController.toggle()
        }
        HotKeyManager.shared.register(.hints, keyCode: kVK_Space, modifiers: controlKey) { [weak self] in
            self?.hintModeController.toggle()
        }

        ClipboardStore.shared.startMonitoring()
        LoginItemManager.ensureRegisteredOnFirstLaunch()
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginMenuItem.state = LoginItemManager.isEnabled ? .on : .off
    }

    @objc private func togglePanel() {
        panelController.toggle()
    }

    @objc private func toggleHintMode() {
        hintModeController.toggle()
    }

    @objc private func toggleLoginItem() {
        LoginItemManager.toggle()
    }
}
