import AppKit

/// 시각별 목표 밝기 스케줄 (Lunar의 시간대 모드를 단순화한 것).
///
/// "07:00 70 · 22:00 30"처럼 등록하면 각 시각부터 다음 시각 전까지가 한 구간이고,
/// 현재 구간의 값을 **앱 시작·잠자기 해제·구간이 바뀔 때** 모든 외장 모니터에 적용한다.
/// 적용 경로는 런처 `밝기 50`과 같은 `DisplayControlManager` 경로라 DDC·감마 모두 된다.
///
/// 사용자가 그 구간 안에서 밝기를 직접 바꾸면(런처·슬라이더·미디어 키) 다음 구간까지는
/// 덮어쓰지 않는다 — 잠자기에서 깨어나도 마찬가지. 이 "직접 바꿈" 기록은 메모리에만
/// 두므로 앱을 다시 켜면 현재 구간 값이 다시 적용된다.
final class BrightnessScheduler {
    static let shared = BrightnessScheduler()

    struct Entry: Codable, Equatable {
        let minute: Int   // 0시부터 분 (0~1439)
        let value: Int    // 0~100

        var timeText: String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    }

    struct Schedule: Codable {
        var enabled: Bool
        var entries: [Entry]   // minute 오름차순
    }

    private let store = JSONFileStore<Schedule>(filename: "brightness-schedule.json", saveDelay: 0.3)
    private(set) var schedule: Schedule

    /// 마지막으로 적용(또는 사용자 조작 때문에 건너뜀)을 마친 구간의 시작 시각
    private var appliedSegment: Date?
    /// 사용자가 직접 밝기를 바꾼 구간의 시작 시각 — 이 구간 동안은 적용하지 않는다
    private var overriddenSegment: Date?
    private var tickTimer: Timer?
    private var wakeWork: DispatchWorkItem?
    /// 깨어난 직후 모니터가 돌아오기 전 — 옛 캐시로 DDC를 쓰면 실패 기록만 쌓이므로 기다린다
    private var waitingForWake = false

    private init() {
        schedule = store.load() ?? Schedule(enabled: false, entries: [])
    }

    /// 앱 시작 시 한 번. 모니터 스캔이 끝나면(onMonitorsChanged) 첫 적용이 일어난다.
    func start() {
        let display = DisplayControlManager.shared
        display.onUserBrightnessChange = { [weak self] in self?.userDidChangeBrightness() }
        display.onMonitorsChanged = { [weak self] in
            self?.waitingForWake = false
            self?.tick()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        // 구간 경계는 분 단위라 30초 주기 확인이면 충분하다 (시계 변경·잠자기에도 강건)
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    // MARK: - 편집

    /// 새 스케줄로 교체하고 켠 뒤 현재 구간 값을 바로 적용한다
    func set(_ entries: [Entry]) {
        schedule = Schedule(enabled: true, entries: entries.sorted { $0.minute < $1.minute })
        store.scheduleSave(schedule)
        overriddenSegment = nil
        appliedSegment = nil
        SpotLog.info("밝기 스케줄 등록 — " + summary, .display)
        tick()
    }

    func setEnabled(_ enabled: Bool) {
        schedule.enabled = enabled
        store.scheduleSave(schedule)
        overriddenSegment = nil
        appliedSegment = nil
        SpotLog.info("밝기 스케줄 " + (enabled ? "켜짐" : "꺼짐"), .display)
        if enabled { tick() }
    }

    /// "07:00 70% · 22:00 30%"
    var summary: String {
        schedule.entries.map { "\($0.timeText) \($0.value)%" }.joined(separator: " · ")
    }

    /// 현재 구간 — 가장 최근에 지난 등록 시각과 그 값. 스케줄이 비었으면 nil.
    func currentSegment(at now: Date = Date()) -> (start: Date, entry: Entry)? {
        let calendar = Calendar.current
        var best: (start: Date, entry: Entry)?
        for entry in schedule.entries {
            guard var start = calendar.date(bySettingHour: entry.minute / 60, minute: entry.minute % 60,
                                            second: 0, of: now) else { continue }
            if start > now, let yesterday = calendar.date(byAdding: .day, value: -1, to: start) {
                start = yesterday
            }
            if best == nil || start > best!.start { best = (start, entry) }
        }
        return best
    }

    /// 현재 구간 안에서 사용자가 직접 밝기를 바꿨는지
    var isOverridden: Bool {
        guard let segment = currentSegment() else { return false }
        return overriddenSegment == segment.start
    }

    // MARK: - 적용

    private func tick() {
        guard schedule.enabled, !waitingForWake,
              let segment = currentSegment(), segment.start != appliedSegment else { return }
        if overriddenSegment == segment.start {
            appliedSegment = segment.start
            return
        }
        // 모니터가 아직 안 잡혔으면(스캔 중·미연결) 표시하지 않고 다음 기회에 다시 시도
        guard DisplayControlManager.shared.applyScheduledBrightness(segment.entry.value) else { return }
        appliedSegment = segment.start
        SpotLog.info("밝기 스케줄 적용 — \(segment.entry.timeText) 구간 \(segment.entry.value)%", .display)
    }

    private func userDidChangeBrightness() {
        guard schedule.enabled, let segment = currentSegment() else { return }
        overriddenSegment = segment.start
    }

    /// 깨어나면 같은 구간이라도 다시 적용한다 (모니터가 꺼졌다 켜지며 자체 밝기로 돌아가는 기종 대비).
    /// 디스플레이 재연결로 재스캔이 돌면 onMonitorsChanged에서 적용되고,
    /// 재스캔이 없는 경우를 위해 몇 초 뒤 한 번 더 확인한다.
    @objc private func workspaceDidWake() {
        appliedSegment = nil
        waitingForWake = true
        wakeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.waitingForWake = false
            self?.tick()
        }
        wakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }
}
