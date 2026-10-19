import Foundation

/// 밝기 스케줄 명령: "밝기 스케줄"(목록), "밝기 스케줄 07:00 70 22:00 30"(등록),
/// "밝기 스케줄 끄기" / "밝기 스케줄 켜기".
final class BrightnessScheduleProvider: SearchProvider {
    private static let keywords = ["밝기", "brightness"]
    private static let scheduleWords: Set<String> = ["스케줄", "스케쥴", "schedule", "일정"]
    private static let offWords: Set<String> = ["끄기", "꺼", "off", "해제", "disable"]
    private static let onWords: Set<String> = ["켜기", "켜", "on", "enable"]

    func results(for query: String) -> [SearchResult] {
        let parts = query.split(separator: " ").map(String.init)
        guard parts.count >= 2,
              Self.scheduleWords.contains(parts[1].lowercased()),
              let baseScore = CommandKeywords.score(parts[0], keywords: Self.keywords) else { return [] }
        let score = baseScore + 2 // "밝기 <이름>" 같은 다른 해석보다 확실히 위
        let args = Array(parts.dropFirst(2))
        let scheduler = BrightnessScheduler.shared

        if args.count == 1, Self.offWords.contains(args[0].lowercased()) {
            return [SearchResult(
                id: "brightness-schedule:off", kind: .systemAction,
                title: "밝기 스케줄 끄기",
                subtitle: scheduler.schedule.entries.isEmpty ? "등록된 스케줄 없음" : scheduler.summary,
                symbolName: "sun.max.trianglebadge.exclamationmark", score: score,
                action: { _ in BrightnessScheduler.shared.setEnabled(false) })]
        }
        if args.count == 1, Self.onWords.contains(args[0].lowercased()) {
            guard !scheduler.schedule.entries.isEmpty else { return [usageResult(score: score)] }
            return [SearchResult(
                id: "brightness-schedule:on", kind: .systemAction,
                title: "밝기 스케줄 켜기",
                subtitle: scheduler.summary,
                symbolName: "sun.max.circle", score: score,
                action: { _ in BrightnessScheduler.shared.setEnabled(true) })]
        }
        if !args.isEmpty {
            guard let entries = Self.parseEntries(args) else { return [usageResult(score: score)] }
            let text = entries.map { "\($0.timeText) \($0.value)%" }.joined(separator: " · ")
            return [SearchResult(
                id: "brightness-schedule:set", kind: .systemAction,
                title: "밝기 스케줄 등록: \(text)",
                subtitle: "각 시각부터 다음 시각까지 그 밝기 — Enter로 저장하고 지금 구간 값 적용",
                symbolName: "sun.max.circle.fill", score: score,
                action: { _ in BrightnessScheduler.shared.set(entries) })]
        }
        return listResults(score: score)
    }

    private func listResults(score: Double) -> [SearchResult] {
        let scheduler = BrightnessScheduler.shared
        let schedule = scheduler.schedule
        guard !schedule.entries.isEmpty else { return [usageResult(score: score)] }

        let current = scheduler.currentSegment()?.entry
        var state = schedule.enabled ? "켜짐" : "꺼짐"
        if schedule.enabled, let current {
            state += " · 지금 \(current.timeText) 구간 \(current.value)%"
            if scheduler.isOverridden { state += " (직접 바꿈 — 다음 구간까지 유지)" }
        }
        var results = [SearchResult(
            id: "brightness-schedule:toggle", kind: .systemAction,
            title: "밝기 스케줄 " + (schedule.enabled ? "끄기" : "켜기"),
            subtitle: state,
            symbolName: schedule.enabled ? "sun.max.circle.fill" : "sun.max.circle", score: score + 0.2,
            action: { _ in BrightnessScheduler.shared.setEnabled(!schedule.enabled) })]
        results += schedule.entries.enumerated().map { index, entry in
            let isCurrent = schedule.enabled && entry == current
            return SearchResult(
                id: "brightness-schedule:entry:\(entry.minute)", kind: .systemAction,
                title: "\(entry.timeText) → 밝기 \(entry.value)%" + (isCurrent ? "  ← 지금" : ""),
                subtitle: "다시 등록하려면 \"밝기 스케줄 07:00 70 22:00 30\"",
                symbolName: "clock", score: score - Double(index) * 0.01, action: { _ in })
        }
        return results
    }

    private func usageResult(score: Double) -> SearchResult {
        SearchResult(
            id: "brightness-schedule:usage", kind: .systemAction,
            title: "밝기 스케줄 07:00 70 22:00 30",
            subtitle: "\"시각 밝기\" 쌍을 이어서 입력 — 시각마다 모든 외장 모니터 밝기를 바꾼다",
            symbolName: "sun.max.circle", score: score, action: { _ in })
    }

    /// ["07:00", "70", "22:00", "30"] → 항목들. 시각은 "7:00"·"07:00"·"7시"·"7시30분", 밝기는 0~100.
    static func parseEntries(_ tokens: [String]) -> [BrightnessScheduler.Entry]? {
        guard !tokens.isEmpty, tokens.count % 2 == 0 else { return nil }
        var entries: [BrightnessScheduler.Entry] = []
        for i in stride(from: 0, to: tokens.count, by: 2) {
            guard let minute = AwakeProvider.parseClockTime(tokens[i]),
                  let value = Int(tokens[i + 1].replacingOccurrences(of: "%", with: "")),
                  (0...100).contains(value),
                  !entries.contains(where: { $0.minute == minute }) else { return nil }
            entries.append(.init(minute: minute, value: value))
        }
        return entries.sorted { $0.minute < $1.minute }
    }
}
