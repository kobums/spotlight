import AppKit
import ServiceManagement

/// SMAppService 기반 로그인 항목 관리. 첫 실행 시 자동 등록하고,
/// 사용자가 시스템 설정에서 직접 끈 경우에는 다시 강제 등록하지 않는다.
enum LoginItemManager {
    private static let didAutoRegisterKey = "didAutoRegisterLoginItem"

    /// .app 번들로 실행 중일 때만 동작 (swift run 바이너리는 등록 불가)
    private static var isRunningFromBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func ensureRegisteredOnFirstLaunch() {
        guard isRunningFromBundle else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didAutoRegisterKey) else { return }
        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: didAutoRegisterKey)
        } catch {
            NSLog("로그인 항목 등록 실패: \(error.localizedDescription)")
        }
    }

    static func toggle() {
        guard isRunningFromBundle else { return }
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: didAutoRegisterKey)
            }
        } catch {
            NSLog("로그인 항목 전환 실패: \(error.localizedDescription)")
        }
    }
}
