import Foundation
import IOKit.pwr_mgt

/// 잠자기 방지 세션 (Amphetamine 방식). IOKit 전원 어설션으로 화면·시스템을 깨워둔다.
/// 권한 불필요, 앱 종료 시 어설션은 자동 해제된다.
final class AwakeSessionManager {
    static let shared = AwakeSessionManager()

    private var assertionID: IOPMAssertionID = 0
    private var endTimer: Timer?

    private(set) var isActive = false
    /// nil이면 무기한 세션
    private(set) var endDate: Date?

    /// 세션 시작/종료 시 호출 (메뉴바 아이콘 갱신용)
    var onChange: (() -> Void)?

    private init() {}

    /// 새 세션 시작. 기존 세션이 있으면 교체. duration이 nil이면 무기한.
    func start(duration: TimeInterval?) {
        end()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Spot 깨어있기 세션" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        isActive = true

        if let duration {
            endDate = Date().addingTimeInterval(duration)
            endTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.end()
            }
        }
        onChange?()
    }

    func end() {
        endTimer?.invalidate()
        endTimer = nil
        if isActive {
            IOPMAssertionRelease(assertionID)
            isActive = false
            endDate = nil
            onChange?()
        }
    }

    /// "46분 남음" / "무기한" — 세션 중이 아니면 nil
    var stateDescription: String? {
        guard isActive else { return nil }
        guard let endDate else { return "무기한" }
        return "\(Self.format(endDate.timeIntervalSinceNow)) 남음"
    }

    static func format(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval.rounded()) / 60, 0)
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)시간 \(m)분" }
        if h > 0 { return "\(h)시간" }
        return "\(max(m, 1))분"
    }
}
