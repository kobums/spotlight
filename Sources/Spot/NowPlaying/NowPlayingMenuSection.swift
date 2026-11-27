import AppKit

/// 메뉴바 메뉴의 "지금 재생 중" 하위 메뉴. 위젯 기능을 쓸 수 없는 환경(macOS 25 이하, `swift run`)에서는 숨긴다.
@MainActor
final class NowPlayingMenuSection: NSObject {
    private let item = NSMenuItem(title: "지금 재생 중 위젯", action: nil, keyEquivalent: "")
    private let submenu = NSMenu()

    /// 메뉴에 넣을 항목. 한 번만 넣고, 열 때마다 `refresh`로 내용을 채운다.
    var menuItem: NSMenuItem {
        item.submenu = submenu
        return item
    }

    func refresh() {
        let service = NowPlayingService.shared
        item.isHidden = !service.isSupported
        guard service.isSupported else { return }

        submenu.removeAllItems()
        for line in statusLines(service) {
            let label = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            label.isEnabled = false
            submenu.addItem(label)
        }
        submenu.addItem(.separator())

        let enabled = NSMenuItem(title: "위젯에 재생 정보 표시", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = service.isEnabled ? .on : .off
        submenu.addItem(enabled)

        let others = NSMenuItem(title: "다른 앱의 재생도 표시", action: #selector(toggleOtherApps), keyEquivalent: "")
        others.target = self
        others.state = service.showsOtherApps ? .on : .off
        submenu.addItem(others)

        // 음악 앱 제어가 꺼져 있으면 앨범 아트·재생 위치·버튼이 빠진다.
        if service.isActive, let monitor = service.monitor {
            switch monitor.permission {
            case .denied:
                submenu.addItem(.separator())
                addAction("음악 앱 제어 허용하기… (시스템 설정)", #selector(requestPermission))
            case .undetermined:
                submenu.addItem(.separator())
                addAction("음악 앱 제어 허용하기…", #selector(requestPermission))
            case .granted, .notRunning:
                break
            }
        }
    }

    private func statusLines(_ service: NowPlayingService) -> [String] {
        guard service.isEnabled else { return ["꺼짐"] }
        guard service.isActive, let monitor = service.monitor else {
            return ["위젯을 추가하면 시작합니다", "바탕화면 control-클릭 › 위젯 편집 › Spot"]
        }
        guard let snapshot = monitor.snapshot, snapshot.hasTrack else { return ["재생 중이 아님"] }
        return snapshot.artist.isEmpty ? [snapshot.title] : [snapshot.title, snapshot.artist]
    }

    private func addAction(_ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        submenu.addItem(item)
    }

    @objc private func toggleEnabled() {
        let service = NowPlayingService.shared
        service.setEnabled(!service.isEnabled)
    }

    @objc private func toggleOtherApps() {
        let service = NowPlayingService.shared
        service.setShowsOtherApps(!service.showsOtherApps)
    }

    @objc private func requestPermission() {
        NowPlayingService.shared.monitor?.requestPermission()
    }
}
