import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var hintModeController: HintModeController!
    private var loginMenuItem: NSMenuItem!
    private var awakeMenuItem: NSMenuItem!
    private var keyRemapMenuItem: NSMenuItem!
    private var mediaKeyMenuItem: NSMenuItem!
    private let displayMenuSection = DisplayMenuSection()

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
        mediaKeyMenuItem = NSMenuItem(title: "모니터 밝기·볼륨 키", action: #selector(toggleMediaKeys), keyEquivalent: "")
        mediaKeyMenuItem.target = self
        menu.addItem(mediaKeyMenuItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
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
        WindowSettingsStore.shared.onChange = { [weak self] in
            self?.registerWindowHotKeys()
        }

        ClipboardStore.shared.startMonitoring()
        LoginItemManager.ensureRegisteredOnFirstLaunch()
        KeyRemapManager.shared.start()
        InputSourceManager.shared.start()
        MediaKeyManager.shared.start()

        AwakeSessionManager.shared.onChange = { [weak self] in
            self?.updateStatusIcon()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // 모니터별 밝기·볼륨 슬라이더 (MonitorControl 스타일) — 열 때마다 최신 값으로
        displayMenuSection.refresh(menu: menu)
        loginMenuItem.state = LoginItemManager.isEnabled ? .on : .off
        if let state = AwakeSessionManager.shared.stateDescription {
            awakeMenuItem.title = "깨어있기 해제 (\(state))"
            awakeMenuItem.state = .on
        } else {
            awakeMenuItem.title = "깨어있기 시작"
            awakeMenuItem.state = .off
        }
        keyRemapMenuItem.state = KeyRemapManager.shared.isEnabled ? .on : .off

        let mediaKeys = MediaKeyManager.shared
        // 앱 실행 뒤에 권한을 준 경우를 위해 메뉴를 열 때마다 한 번 더 붙여 본다
        mediaKeys.start()
        mediaKeyMenuItem.state = mediaKeys.isEnabled ? .on : .off
        // 켜져 있는데 탭이 안 붙었으면 손쉬운 사용 권한이 없다는 뜻 — 이유를 드러낸다
        mediaKeyMenuItem.title = mediaKeys.isEnabled && !mediaKeys.isRunning
            ? "모니터 밝기·볼륨 키 (손쉬운 사용 권한 필요)"
            : "모니터 밝기·볼륨 키"
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

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func toggleLoginItem() {
        LoginItemManager.toggle()
    }

    /// 액션 ↔ 핫키 ID 대응 (핫키 재등록 시 어떤 ID를 해제할지 결정)
    private static let windowHotKeyIDs: [WindowAction: HotKeyManager.HotKeyID] = [
        .leftHalf: .windowLeftHalf, .rightHalf: .windowRightHalf,
        .topHalf: .windowTopHalf, .bottomHalf: .windowBottomHalf,
        .topLeft: .windowTopLeft, .topRight: .windowTopRight,
        .bottomLeft: .windowBottomLeft, .bottomRight: .windowBottomRight,
        .maximize: .windowMaximize, .maximizeHeight: .windowMaximizeHeight,
        .center: .windowCenter, .restore: .windowRestore,
        .smaller: .windowSmaller, .larger: .windowLarger,
        .nextDisplay: .windowNextDisplay, .previousDisplay: .windowPrevDisplay,
    ]

    /// 설정에 저장된 창 배치 전역 단축키를 등록한다 (기본값 = Rectangle에서 쓰던 조합).
    /// 설정 창에서 바뀌면 onChange로 다시 불려 전체 재등록된다.
    private func registerWindowHotKeys() {
        let shortcuts = WindowSettingsStore.shared.settings.shortcuts
        for (action, id) in Self.windowHotKeyIDs {
            HotKeyManager.shared.unregister(id)
            guard let combo = shortcuts[action.rawValue] else { continue }
            HotKeyManager.shared.register(id, keyCode: combo.keyCode, modifiers: combo.carbonModifiers) {
                WindowManager.shared.perform(action)
            }
        }
    }

    @objc private func toggleKeyRemap() {
        KeyRemapManager.shared.setEnabled(!KeyRemapManager.shared.isEnabled)
    }

    /// 꺼져 있으면 켜고, 켜져 있는데 권한이 없어 탭이 안 붙었으면 다시 권한을 요청한다
    @objc private func toggleMediaKeys() {
        let manager = MediaKeyManager.shared
        if manager.isEnabled && manager.isRunning {
            manager.setEnabled(false)
        } else {
            manager.setEnabled(true)
        }
    }

    @objc private func toggleAwake() {
        let manager = AwakeSessionManager.shared
        manager.isActive ? manager.end() : manager.start(duration: nil)
    }
}
