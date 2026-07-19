import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var hintModeController: HintModeController!
    private var loginMenuItem: NSMenuItem!
    private var awakeMenuItem: NSMenuItem!
    private var keyRemapMenuItem: NSMenuItem!

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
        awakeMenuItem = NSMenuItem(title: "깨어있기 시작", action: #selector(toggleAwake), keyEquivalent: "")
        awakeMenuItem.target = self
        menu.addItem(awakeMenuItem)
        keyRemapMenuItem = NSMenuItem(title: "키 리맵 (우측⌘ 한/영 · Caps→⌃)", action: #selector(toggleKeyRemap), keyEquivalent: "")
        keyRemapMenuItem.target = self
        menu.addItem(keyRemapMenuItem)
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
        registerWindowHotKeys()

        ClipboardStore.shared.startMonitoring()
        LoginItemManager.ensureRegisteredOnFirstLaunch()
        KeyRemapManager.shared.start()

        AwakeSessionManager.shared.onChange = { [weak self] in
            self?.updateStatusIcon()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginMenuItem.state = LoginItemManager.isEnabled ? .on : .off
        if let state = AwakeSessionManager.shared.stateDescription {
            awakeMenuItem.title = "깨어있기 해제 (\(state))"
            awakeMenuItem.state = .on
        } else {
            awakeMenuItem.title = "깨어있기 시작"
            awakeMenuItem.state = .off
        }
        keyRemapMenuItem.state = KeyRemapManager.shared.isEnabled ? .on : .off
    }

    /// 깨어있기 세션 중에는 메뉴바 아이콘을 컵으로 바꿔 상태를 드러낸다
    private func updateStatusIcon() {
        let symbol = AwakeSessionManager.shared.isActive ? "cup.and.saucer.fill" : "sparkle.magnifyingglass"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Spot")
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

    /// Rectangle에서 쓰던 창 배치 전역 단축키를 그대로 등록한다.
    /// 창 모드(힌트에서 ".")와 별개로, 근육 기억대로 바로 실행하는 경로.
    private func registerWindowHotKeys() {
        let bindings: [(HotKeyManager.HotKeyID, Int, Int, WindowAction)] = [
            (.windowLeftHalf, kVK_LeftArrow, optionKey | cmdKey, .leftHalf),        // ⌥⌘←
            (.windowRightHalf, kVK_RightArrow, optionKey | cmdKey, .rightHalf),     // ⌥⌘→
            (.windowTopHalf, kVK_UpArrow, optionKey | cmdKey, .topHalf),            // ⌥⌘↑
            (.windowBottomHalf, kVK_DownArrow, optionKey | cmdKey, .bottomHalf),    // ⌥⌘↓
            (.windowTopLeft, kVK_LeftArrow, controlKey | cmdKey, .topLeft),         // ⌃⌘←
            (.windowTopRight, kVK_RightArrow, controlKey | cmdKey, .topRight),      // ⌃⌘→
            (.windowBottomLeft, kVK_LeftArrow, controlKey | shiftKey | cmdKey, .bottomLeft),    // ⌃⇧⌘←
            (.windowBottomRight, kVK_RightArrow, controlKey | shiftKey | cmdKey, .bottomRight), // ⌃⇧⌘→
            (.windowMaximize, kVK_ANSI_F, optionKey | cmdKey, .maximize),           // ⌥⌘F
            (.windowMaximizeHeight, kVK_UpArrow, controlKey | optionKey | shiftKey, .maximizeHeight), // ⌃⌥⇧↑
            (.windowCenter, kVK_ANSI_C, optionKey | cmdKey, .center),               // ⌥⌘C
            (.windowRestore, kVK_Delete, controlKey | optionKey, .restore),         // ⌃⌥⌫
            (.windowSmaller, kVK_LeftArrow, controlKey | optionKey | shiftKey, .smaller),  // ⌃⌥⇧←
            (.windowLarger, kVK_RightArrow, controlKey | optionKey | shiftKey, .larger),   // ⌃⌥⇧→
            (.windowNextDisplay, kVK_RightArrow, controlKey | optionKey | cmdKey, .nextDisplay),     // ⌃⌥⌘→
            (.windowPrevDisplay, kVK_LeftArrow, controlKey | optionKey | cmdKey, .previousDisplay),  // ⌃⌥⌘←
        ]
        for (id, keyCode, modifiers, action) in bindings {
            HotKeyManager.shared.register(id, keyCode: keyCode, modifiers: modifiers) {
                WindowManager.shared.perform(action)
            }
        }
    }

    @objc private func toggleKeyRemap() {
        KeyRemapManager.shared.setEnabled(!KeyRemapManager.shared.isEnabled)
    }

    @objc private func toggleAwake() {
        let manager = AwakeSessionManager.shared
        manager.isActive ? manager.end() : manager.start(duration: nil)
    }
}
