import AppKit

/// 입력 소스 명령 (Input Source Pro 대체):
/// "입력규칙" — 최전면 앱의 입력 소스 규칙 등록/제거 (패널이 포커스를 안 뺏는 특성 활용),
/// "입력규칙 목록" — 등록된 규칙 전체, "입력소스"/"한영" — 수동 전환.
final class InputSourceProvider: SearchProvider {
    private static let ruleKeywords = ["입력규칙", "input rule", "한영규칙"]
    private static let switchKeywords = ["입력소스", "한영", "input source"]

    func results(for query: String) -> [SearchResult] {
        let parts = query.split(separator: " ").map(String.init)
        guard let first = parts.first else { return [] }
        let rest = parts.dropFirst().joined(separator: " ")

        if let score = bestScore(first, in: Self.ruleKeywords) {
            if rest == "목록" || rest == "list" { return ruleListResults(score: score) }
            guard rest.isEmpty else { return [] }
            return ruleResults(score: score)
        }
        if let score = bestScore(first, in: Self.switchKeywords), rest.isEmpty {
            return switchResults(score: score)
        }
        return []
    }

    private func bestScore(_ needle: String, in keywords: [String]) -> Double? {
        let scores = keywords.compactMap { FuzzyMatch.score(needle: needle, haystack: $0) }
        guard let best = scores.max() else { return nil }
        return (best.isInfinite ? Score.actionExact : best) + Score.actionBonus
    }

    // MARK: - 규칙 등록 (최전면 앱 대상)

    private func ruleResults(score: Double) -> [SearchResult] {
        let manager = InputSourceManager.shared
        guard let app = HintTargetCollector.frontmostApp(),
              let bundleID = app.bundleIdentifier else { return [] }
        let appName = app.localizedName ?? bundleID
        let existing = manager.rule(for: bundleID)

        var out: [SearchResult] = []
        for source in manager.sources {
            let isCurrent = existing == source.id
            out.append(SearchResult(
                id: "inputrule:\(bundleID):\(source.id)",
                kind: .systemAction,
                title: "\(appName) → 항상 \(source.name)\(isCurrent ? " (현재 규칙)" : "")",
                subtitle: "이 앱이 활성화되면 자동으로 전환",
                symbolName: "keyboard.badge.ellipsis",
                score: score + (isCurrent ? 0 : 1),
                action: { _ in InputSourceManager.shared.setRule(bundleID: bundleID, sourceID: source.id) }
            ))
        }
        if let existing {
            out.append(SearchResult(
                id: "inputrule:remove:\(bundleID)",
                kind: .systemAction,
                title: "\(appName) 규칙 제거",
                subtitle: "현재: \(manager.sourceName(for: existing)) — \"입력규칙 목록\"으로 전체 보기",
                symbolName: "keyboard.badge.eye",
                score: score + 2,
                action: { _ in InputSourceManager.shared.setRule(bundleID: bundleID, sourceID: nil) }
            ))
        }
        return out
    }

    private func ruleListResults(score: Double) -> [SearchResult] {
        let manager = InputSourceManager.shared
        guard !manager.rules.isEmpty else {
            return [SearchResult(
                id: "inputrule:empty", kind: .systemAction,
                title: "등록된 입력 소스 규칙 없음",
                subtitle: "대상 앱을 앞에 두고 \"입력규칙\"으로 등록",
                symbolName: "keyboard", score: score, action: { _ in })]
        }
        return manager.rules.map { bundleID, sourceID in
            let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
            return SearchResult(
                id: "inputrule:list:\(bundleID)",
                kind: .systemAction,
                title: "\(appName) → \(manager.sourceName(for: sourceID))",
                subtitle: "Enter로 규칙 제거",
                symbolName: "keyboard",
                score: score,
                action: { _ in InputSourceManager.shared.setRule(bundleID: bundleID, sourceID: nil) })
        }
    }

    // MARK: - 수동 전환

    private func switchResults(score: Double) -> [SearchResult] {
        let manager = InputSourceManager.shared
        let currentID = manager.current?.id
        return manager.sources.map { source in
            let isCurrent = source.id == currentID
            return SearchResult(
                id: "inputsource:\(source.id)",
                kind: .systemAction,
                title: "\(source.name)\(isCurrent ? " (현재)" : "")로 전환",
                subtitle: "입력 소스",
                symbolName: source.badge == "한" ? "textformat.alt" : "textformat.abc",
                score: score + (isCurrent ? 0 : 1),
                action: { _ in InputSourceManager.shared.select(id: source.id) })
        }
    }
}
