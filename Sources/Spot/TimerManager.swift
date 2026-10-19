import AppKit
import UserNotifications

/// 타이머·알람. 끝나면 알림 센터 알림 + 소리.
///
/// 만료 판정은 1초 주기 틱에서 `fireDate <= 지금`으로 한다 — 개별 Timer는 잠자기 동안
/// 멈춰 깨어난 뒤 늦게 울리지만, 벽시계 비교는 깨어나자마자 울린다. 같은 틱으로 메뉴바
/// 남은 시간도 갱신한다. 목록은 메모리에만 있어 앱을 끄면 사라진다 (깨어있기 세션과 같음).
final class TimerManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TimerManager()

    struct Item {
        enum Kind { case timer, alarm }
        let id = UUID()
        let kind: Kind
        let fireDate: Date
        let duration: TimeInterval   // 타이머: 설정 시간, 알람: 설정 시점부터 남은 시간
        let label: String?

        /// "10분 타이머" / "15:30 알람" (+ 라벨)
        var title: String {
            let base: String
            switch kind {
            case .timer: base = "\(AwakeSessionManager.format(duration)) 타이머"
            case .alarm: base = "\(TimerManager.clockFormatter.string(from: fireDate)) 알람"
            }
            return label.map { "\(base) — \($0)" } ?? base
        }
    }

    /// 울릴 순서(fireDate 오름차순)
    private(set) var items: [Item] = []
    /// 추가·취소·만료 시 (메뉴바 갱신용). 남은 시간 갱신은 onTick.
    var onChange: (() -> Void)?
    /// 동작 중 1초마다 (메뉴바 카운트다운용)
    var onTick: (() -> Void)?

    private var tickTimer: Timer?
    private var didRequestAuthorization = false

    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private override init() {}

    // MARK: - 추가·취소

    func addTimer(duration: TimeInterval, label: String?) {
        add(Item(kind: .timer, fireDate: Date().addingTimeInterval(duration), duration: duration, label: label))
    }

    /// 0시부터 minute분인 다음 시각(오늘 지났으면 내일)에 울린다
    func addAlarm(minute: Int, label: String?) {
        let date = Self.nextOccurrence(ofMinute: minute)
        add(Item(kind: .alarm, fireDate: date, duration: date.timeIntervalSinceNow, label: label))
    }

    func cancel(_ id: UUID) {
        items.removeAll { $0.id == id }
        changed()
    }

    func cancelAll() {
        items.removeAll()
        changed()
    }

    private func add(_ item: Item) {
        requestAuthorizationIfNeeded()
        items.append(item)
        items.sort { $0.fireDate < $1.fireDate }
        SpotLog.info("타이머 추가 — \(item.title) (\(Self.clockFormatter.string(from: item.fireDate))에 울림)")
        changed()
    }

    private func changed() {
        if items.isEmpty {
            tickTimer?.invalidate()
            tickTimer = nil
        } else if tickTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.1
            // 메뉴가 열려 있는 동안(이벤트 추적 모드)에도 카운트다운이 멈추지 않게
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        }
        onChange?()
    }

    private func tick() {
        let now = Date()
        let due = items.filter { $0.fireDate <= now }
        if !due.isEmpty {
            items.removeAll { $0.fireDate <= now }
            due.forEach(ring)
            changed()
        }
        onTick?()
    }

    // MARK: - 표시

    /// 가장 먼저 울릴 항목의 남은 시간 — 메뉴바 제목용. 없으면 nil.
    var menuBarText: String? {
        items.first.map { Self.countdown($0.fireDate.timeIntervalSinceNow) }
    }

    /// "9:41" / "1:29:59"
    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.up)), 0)
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func nextOccurrence(ofMinute minute: Int, after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: now) ?? now
        return today > now ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    // MARK: - 울림

    private func ring(_ item: Item) {
        SpotLog.info("타이머 종료 — \(item.title)")
        let body = item.kind == .timer ? "시간이 다 됐습니다" : "알람 시각입니다"
        notify(title: item.title, body: body)
        // 짧은 효과음이라 세 번 울려 놓치지 않게
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.2) {
                NSSound(named: "Glass")?.play()
            }
        }
    }

    /// 알림 센터는 번들(.app)로 실행될 때만 쓸 수 있다 — `swift run` 같은 맨 실행 파일에서
    /// UNUserNotificationCenter.current()를 부르면 예외로 죽는다.
    private var canUseNotificationCenter: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private func requestAuthorizationIfNeeded() {
        guard canUseNotificationCenter, !didRequestAuthorization else { return }
        didRequestAuthorization = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted {
                SpotLog.info("알림 권한 없음 — 타이머 종료는 소리로만 알림"
                             + (error.map { " (\($0.localizedDescription))" } ?? ""))
            }
        }
    }

    private func notify(title: String, body: String) {
        guard canUseNotificationCenter else {
            // 개발 실행용 폴백 — osascript 알림 (Script Editor 이름으로 뜬다)
            let script = "display notification \(Self.appleScriptString(body)) with title \(Self.appleScriptString(title))"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 소리는 NSSound로 직접 낸다 (알림 설정에서 소리를 꺼 둬도 들리게)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// 런처 패널이 떠 있어 Spot이 활성 앱이어도 배너를 보여준다
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
