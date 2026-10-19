import Foundation

/// 타이머·알람 명령: "타이머 10분", "타이머 1시간 30분 라면", "알람 15:30", "알람 오후 3시 회의".
/// 키워드만 입력하면 동작 중인 목록 — Enter로 그 항목 취소. "타이머 취소"는 전체 취소.
final class TimerProvider: SearchProvider {
    private static let timerKeywords = ["타이머", "timer"]
    private static let alarmKeywords = ["알람", "alarm"]
    private static let cancelWords: Set<String> = ["취소", "끄기", "cancel", "stop", "off"]

    func results(for query: String) -> [SearchResult] {
        let parts = query.split(separator: " ").map(String.init)
        guard let first = parts.first else { return [] }
        let timerScore = CommandKeywords.score(first, keywords: Self.timerKeywords)
        let alarmScore = CommandKeywords.score(first, keywords: Self.alarmKeywords)
        guard let baseScore = [timerScore, alarmScore].compactMap({ $0 }).max() else { return [] }
        let isAlarm = (alarmScore ?? -.infinity) > (timerScore ?? -.infinity)
        let args = Array(parts.dropFirst())

        if args.count == 1, Self.cancelWords.contains(args[0].lowercased()) {
            let items = TimerManager.shared.items
            guard !items.isEmpty else { return [emptyResult(isAlarm: isAlarm, score: baseScore)] }
            return [SearchResult(
                id: "timer:cancel-all", kind: .systemAction,
                title: items.count == 1 ? "\(items[0].title) 취소" : "타이머·알람 \(items.count)개 모두 취소",
                subtitle: items.map(\.title).joined(separator: " · "),
                symbolName: "xmark.circle", score: baseScore + 2,
                action: { _ in TimerManager.shared.cancelAll() })]
        }

        var results: [SearchResult] = []
        if !args.isEmpty {
            // 시간으로 해석되지 않으면 담당 아님 (파일 검색 등에 양보)
            guard let create = isAlarm
                    ? alarmResult(args, score: baseScore + 2)
                    : timerResult(args, score: baseScore + 2) else { return [] }
            results.append(create)
        }
        results += listResults(score: baseScore)
        if results.isEmpty { results.append(emptyResult(isAlarm: isAlarm, score: baseScore)) }
        return results
    }

    private func timerResult(_ args: [String], score: Double) -> SearchResult? {
        guard let (duration, label) = Self.split(args, parse: { AwakeProvider.parseDuration($0) }) else { return nil }
        let end = TimerManager.clockFormatter.string(from: Date().addingTimeInterval(duration))
        return SearchResult(
            id: "timer:new", kind: .systemAction,
            title: "\(TimerManager.format(duration)) 타이머 시작" + (label.map { " — \($0)" } ?? ""),
            subtitle: "\(end)에 알림과 소리 · 메뉴바에 남은 시간 표시",
            symbolName: "timer", score: score,
            action: { _ in TimerManager.shared.addTimer(duration: duration, label: label) })
    }

    private func alarmResult(_ args: [String], score: Double) -> SearchResult? {
        guard let (minute, label) = Self.split(args, parse: { AwakeProvider.parseClockTime($0) }) else { return nil }
        let date = TimerManager.nextOccurrence(ofMinute: minute)
        let day = Calendar.current.isDateInToday(date) ? "오늘" : "내일"
        return SearchResult(
            id: "timer:alarm:new", kind: .systemAction,
            title: "\(TimerManager.clockFormatter.string(from: date)) 알람 설정" + (label.map { " — \($0)" } ?? ""),
            subtitle: "\(day) · \(AwakeSessionManager.format(date.timeIntervalSinceNow)) 후 알림과 소리",
            symbolName: "alarm", score: score,
            action: { _ in TimerManager.shared.addAlarm(minute: minute, label: label) })
    }

    /// 동작 중인 타이머·알람 — Enter로 취소
    private func listResults(score: Double) -> [SearchResult] {
        TimerManager.shared.items.enumerated().map { index, item in
            SearchResult(
                id: "timer:item:\(item.id)", kind: .systemAction,
                title: "\(item.title) — \(TimerManager.countdown(item.fireDate.timeIntervalSinceNow)) 남음",
                subtitle: "\(TimerManager.clockFormatter.string(from: item.fireDate))에 울림 · Enter로 취소",
                symbolName: item.kind == .timer ? "timer" : "alarm",
                score: score + 1 - Double(index) * 0.01,
                action: { _ in TimerManager.shared.cancel(item.id) })
        }
    }

    private func emptyResult(isAlarm: Bool, score: Double) -> SearchResult {
        SearchResult(
            id: "timer:usage", kind: .systemAction,
            title: isAlarm ? "알람 15:30" : "타이머 10분",
            subtitle: isAlarm
                ? "동작 중인 알람 없음 — \"알람 7:30\", \"알람 오후 3시 회의\""
                : "동작 중인 타이머 없음 — \"타이머 1시간 30분\", \"타이머 3분 라면\"",
            symbolName: isAlarm ? "alarm" : "timer", score: score, action: { _ in })
    }

    /// 앞쪽 토큰 중 시간으로 해석되는 가장 긴 접두를 값으로, 나머지를 라벨로.
    /// "1시간 30분 라면" → (5400, "라면")
    private static func split<T>(_ tokens: [String], parse: (String) -> T?) -> (T, String?)? {
        for count in stride(from: tokens.count, through: 1, by: -1) {
            guard let value = parse(tokens.prefix(count).joined(separator: " ")) else { continue }
            let rest = tokens.dropFirst(count).joined(separator: " ")
            return (value, rest.isEmpty ? nil : rest)
        }
        return nil
    }
}
