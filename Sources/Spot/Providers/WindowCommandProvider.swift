import AppKit

/// "창 왼쪽", "창 최대화" 등 런처에서 창 배치 실행.
/// 창 모드·전역 단축키와 같은 WindowManager 액션을 쓴다 — 패널이 포커스를
/// 안 뺏으므로 최전면 창이 그대로 대상이 된다.
final class WindowCommandProvider: SearchProvider {
    private static let keywords = ["창", "window", "win"]

    /// displayName 외에 통용되는 별칭 (한글·영문)
    private static let aliases: [WindowAction: [String]] = [
        .leftHalf: ["왼쪽", "left", "좌"],
        .rightHalf: ["오른쪽", "right", "우"],
        .topHalf: ["위쪽", "위", "top"],
        .bottomHalf: ["아래쪽", "아래", "bottom"],
        .topLeft: ["왼쪽위", "top left"],
        .topRight: ["오른쪽위", "top right"],
        .bottomLeft: ["왼쪽아래", "bottom left"],
        .bottomRight: ["오른쪽아래", "bottom right"],
        .maximize: ["최대화", "maximize", "max", "풀"],
        .maximizeHeight: ["높이최대화", "height"],
        .center: ["가운데", "중앙", "center"],
        .restore: ["복원", "restore"],
        .smaller: ["작게", "smaller"],
        .larger: ["크게", "larger"],
        .nextDisplay: ["다음디스플레이", "다음모니터", "next display"],
        .previousDisplay: ["이전디스플레이", "이전모니터", "previous display"],
    ]

    private static let symbols: [WindowAction: String] = [
        .leftHalf: "rectangle.lefthalf.filled",
        .rightHalf: "rectangle.righthalf.filled",
        .topHalf: "rectangle.tophalf.filled",
        .bottomHalf: "rectangle.bottomhalf.filled",
        .topLeft: "rectangle.inset.topleft.filled",
        .topRight: "rectangle.inset.topright.filled",
        .bottomLeft: "rectangle.inset.bottomleft.filled",
        .bottomRight: "rectangle.inset.bottomright.filled",
        .maximize: "rectangle.fill",
        .maximizeHeight: "rectangle.portrait.fill",
        .center: "rectangle.center.inset.filled",
        .restore: "arrow.uturn.backward",
        .smaller: "minus.rectangle",
        .larger: "plus.rectangle",
        .nextDisplay: "arrow.right.square",
        .previousDisplay: "arrow.left.square",
    ]

    func results(for query: String) -> [SearchResult] {
        let parts = query.split(separator: " ", maxSplits: 1)
        guard let first = parts.first,
              let baseScore = CommandKeywords.score(String(first), keywords: Self.keywords) else { return [] }

        let term = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        let ordered = WindowAction.allCases

        let matched: [(WindowAction, Double)]
        if term.isEmpty {
            // "창"만 입력 — 전체 목록을 정의 순서대로
            matched = ordered.enumerated().map { ($0.element, baseScore - Double($0.offset) * 0.01) }
        } else {
            matched = ordered.compactMap { action in
                let names = [action.displayName] + (Self.aliases[action] ?? [])
                let scores = names.compactMap { FuzzyMatch.score(needle: term, haystack: $0) }
                guard let best = scores.max() else { return nil }
                return (action, baseScore + (best.isInfinite ? 10 : best))
            }
        }
        guard !matched.isEmpty else { return [] }

        return matched.map { action, score in
            SearchResult(
                id: "wincmd:\(action.rawValue)",
                kind: .systemAction,
                title: "창: \(action.displayName)",
                subtitle: "최전면 창 배치",
                symbolName: Self.symbols[action] ?? "macwindow",
                score: score,
                action: { _ in WindowManager.shared.perform(action) }
            )
        }
    }
}
