import Foundation

/// 잠자기 방지 세션 검색: "깨어있기", "awake 30분", "카페인 2시간" 등.
/// "<키워드> [시간]" 형태 — 시간이 없으면 무기한 세션.
final class AwakeProvider: SearchProvider {
    private static let keywords = ["깨어있기", "awake", "caffeine", "카페인", "커피"]

    func results(for query: String) -> [SearchResult] {
        let parts = query.split(separator: " ", maxSplits: 1)
        guard let first = parts.first else { return [] }
        let keywordScores = Self.keywords.compactMap {
            FuzzyMatch.score(needle: String(first), haystack: $0)
        }
        guard let best = keywordScores.max() else { return [] }
        let baseScore = (best.isInfinite ? Score.actionExact : best) + Score.actionBonus

        let durationText = parts.count > 1 ? String(parts[1]) : ""
        let duration = Self.parseDuration(durationText)
        // 키워드 뒤에 붙은 텍스트가 시간으로 해석되지 않으면 담당 아님
        if !durationText.isEmpty && duration == nil { return [] }

        let manager = AwakeSessionManager.shared
        var out: [SearchResult] = []

        if manager.isActive {
            out.append(SearchResult(
                id: "awake:stop",
                kind: .systemAction,
                title: "깨어있기 해제",
                subtitle: manager.stateDescription ?? "",
                symbolName: "cup.and.saucer",
                score: baseScore + 1, // 세션 중엔 해제가 최우선
                action: { _ in AwakeSessionManager.shared.end() }
            ))
        }
        if let duration {
            out.append(SearchResult(
                id: "awake:timed",
                kind: .systemAction,
                title: "\(AwakeSessionManager.format(duration)) 동안 깨어있기",
                subtitle: "잠자기 방지 — 시간이 지나면 자동 해제",
                symbolName: "cup.and.saucer.fill",
                score: baseScore + 2, // 시간을 입력했으면 그게 의도
                action: { _ in AwakeSessionManager.shared.start(duration: duration) }
            ))
        } else {
            out.append(SearchResult(
                id: "awake:start",
                kind: .systemAction,
                title: "무기한 깨어있기",
                subtitle: "잠자기 방지 — 해제할 때까지 (예: \"awake 30분\")",
                symbolName: "cup.and.saucer.fill",
                score: baseScore,
                action: { _ in AwakeSessionManager.shared.start(duration: nil) }
            ))
        }
        return out
    }

    /// "30분", "2시간", "1시간 30분", "90m", "2h", "45"(분 해석) → 초
    static func parseDuration(_ text: String) -> TimeInterval? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        if let n = Double(t), n > 0 { return n * 60 } // 숫자만 → 분

        let pattern = #"(\d+(?:\.\d+)?)\s*(시간|hours?|hrs?|h|분|minutes?|mins?|m)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = t as NSString
        var total: TimeInterval = 0
        var matchedLength = 0
        for match in regex.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            let value = Double(ns.substring(with: match.range(at: 1))) ?? 0
            let unit = ns.substring(with: match.range(at: 2))
            let isHour = unit.hasPrefix("시간") || unit.hasPrefix("h")
            total += value * (isHour ? 3600 : 60)
            matchedLength += match.range.length
        }
        // 시간 표현 외의 잡음이 섞여 있으면 실패 처리 ("awake abc" 등)
        let stripped = t.replacingOccurrences(of: " ", with: "")
        guard total > 0, matchedLength >= stripped.count else { return nil }
        return total
    }
}
