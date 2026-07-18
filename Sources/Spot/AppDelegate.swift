import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = PanelController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Spot")
        }
        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Spot 열기 (⌥Space)", action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu

        HotKeyManager.shared.handler = { [weak self] in
            self?.panelController.toggle()
        }
        HotKeyManager.shared.register()

        ClipboardStore.shared.startMonitoring()
    }

    @objc private func togglePanel() {
        panelController.toggle()
    }
}
