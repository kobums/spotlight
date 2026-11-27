import AppKit
import OSLog
import WidgetKit

/// "지금 재생 중" 위젯에 재생 정보를 대 주는 기능의 진입점 (따로 있던 NowPlaying 앱을 합친 것).
///
/// 위젯은 Spot.app 안의 확장(`PlugIns/SpotWidget.appex`)이고, 재생 상태는 Spot이 App Group 폴더에 써 준다.
/// 다음을 모두 만족할 때만 돈다.
/// - macOS 26 이상 (위젯 확장의 최소 버전)
/// - 팀 서명된 앱 번들로 실행 (App Group은 서명의 권한에서 온다. `swift run`·ad-hoc 빌드에는 없다)
/// - 메뉴에서 꺼 두지 않았고, 위젯이 실제로 놓여 있음
///
/// 위젯을 쓰지 않는 사람에게는 음악 앱 제어 허락을 묻지 않고 도우미(perl)도 띄우지 않는다.
@MainActor
final class NowPlayingService {
    static let shared = NowPlayingService()

    private static let enabledKey = "nowPlayingEnabled"
    private let log = Logger(subsystem: "com.gowoobro.spot.nowplaying", category: "service")
    private(set) var monitor: MusicMonitor?
    private var didStart = false
    private var isCheckingWidget = false

    /// 이 실행 환경에서 위젯 기능을 쓸 수 있는지. 못 쓰면 메뉴에도 내놓지 않는다.
    let isSupported: Bool = {
        guard #available(macOS 26.0, *) else { return false }
        return AppGroup.containerURL != nil
    }()

    /// 메뉴의 "위젯에 재생 정보 표시". 켜져 있는 것이 기본이다.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// 재생 상태를 따라가는 중인지 (켜져 있고 위젯이 놓여 있다).
    var isActive: Bool { monitor?.isRunning == true }

    var showsOtherApps: Bool { monitor?.showsOtherApps ?? MusicMonitor.storedShowsOtherApps }

    /// 앱이 켜질 때 한 번 부른다.
    func start() {
        guard isSupported, !didStart else { return }
        didStart = true
        // 앱이 켜진 뒤에 위젯을 추가한 경우. 이 알림은 같은 사용자의 어떤 프로세스든 보낼 수 있으므로
        // 그대로 믿지 않고, 위젯이 실제로 놓여 있는지 확인한 뒤에 켠다.
        // 막 추가한 위젯은 목록에 조금 늦게 나타날 수 있어 한 번 더 본다.
        WidgetPresence.observe { [weak self] in
            MainActor.assumeIsolated {
                self?.activateIfWidgetIsPlaced(reason: "위젯이 그려짐", retryAfter: .seconds(2))
            }
        }
        activateIfWidgetIsPlaced(reason: "위젯이 놓여 있음")
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupported, enabled != isEnabled else { return }
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            activateIfWidgetIsPlaced(reason: "메뉴에서 켬")
        } else {
            monitor?.stop()
        }
    }

    func setShowsOtherApps(_ enabled: Bool) {
        if let monitor {
            monitor.setShowsOtherApps(enabled)
        } else {
            MusicMonitor.storedShowsOtherApps = enabled
        }
    }

    /// 위젯을 눌러 `spot://now-playing`으로 불렸을 때: 재생 중인 앱을 앞으로 가져온다.
    /// - Returns: 이 기능의 주소였는지.
    func handle(_ url: URL) -> Bool {
        guard url.scheme == DeepLink.scheme, url.host == DeepLink.host else { return false }
        if let monitor, monitor.isRunning {
            monitor.openSource()
        } else if let music = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicBridge.bundleID) {
            NSWorkspace.shared.openApplication(at: music, configuration: NSWorkspace.OpenConfiguration())
        }
        return true
    }

    // MARK: - 위젯이 놓여 있을 때만 켜기

    /// - Parameter retryAfter: 위젯이 안 보이면 이만큼 뒤에 한 번 더 확인한다.
    private func activateIfWidgetIsPlaced(reason: String, retryAfter: Duration? = nil) {
        // 켜져 있는 동안에는 위젯이 그려질 때마다 알림이 온다. 그때마다 묻지 않는다.
        guard isSupported, isEnabled, !isActive, !isCheckingWidget else { return }
        isCheckingWidget = true
        WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
            let placed: Bool
            var failure: String?
            switch result {
            case .success(let widgets):
                placed = widgets.contains { $0.kind == WidgetKind.nowPlaying }
            case .failure(let error):
                placed = false
                failure = error.localizedDescription
            }
            Task { @MainActor in
                guard let self else { return }
                self.isCheckingWidget = false
                if let failure {
                    self.log.error("놓인 위젯을 확인하지 못함: \(failure, privacy: .public)")
                }
                if placed {
                    self.activate(reason: reason)
                } else if let retryAfter {
                    try? await Task.sleep(for: retryAfter)
                    self.activateIfWidgetIsPlaced(reason: reason)
                }
            }
        }
    }

    private func activate(reason: String) {
        guard isSupported, isEnabled, !isActive else { return }
        log.info("시작: \(reason, privacy: .public)")
        let monitor = monitor ?? MusicMonitor()
        self.monitor = monitor
        monitor.start()
    }
}
