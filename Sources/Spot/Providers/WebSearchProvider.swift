import AppKit

/// 웹 검색 키워드: "g 검색어"(구글), "yt"(유튜브), "gh"(깃허브), "nv"(네이버).
/// 매칭 결과가 없으면 항상 마지막에 구글 검색 폴백 제공.
final class WebSearchProvider: SearchProvider {

    private struct Engine {
        let prefix: String
        let name: String
        let urlTemplate: String
        let symbol: String
    }

    private let engines = [
        Engine(prefix: "g", name: "Google", urlTemplate: "https://www.google.com/search?q=%@", symbol: "magnifyingglass"),
        Engine(prefix: "yt", name: "YouTube", urlTemplate: "https://www.youtube.com/results?search_query=%@", symbol: "play.rectangle.fill"),
        Engine(prefix: "gh", name: "GitHub", urlTemplate: "https://github.com/search?q=%@", symbol: "chevron.left.forwardslash.chevron.right"),
        Engine(prefix: "nv", name: "네이버", urlTemplate: "https://search.naver.com/search.naver?query=%@", symbol: "n.square.fill"),
    ]

    /// 접두사 매치 시 상단 노출용 결과
    func results(for query: String) -> [SearchResult] {
        for engine in engines {
            let p = engine.prefix + " "
            guard query.lowercased().hasPrefix(p), query.count > p.count else { continue }
            let term = String(query.dropFirst(p.count))
            return [makeResult(engine: engine, term: term, score: Score.webPrefix)]
        }
        return []
    }

    /// 항상 목록 끝에 붙는 구글 폴백
    func fallbackResult(for query: String) -> SearchResult? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return makeResult(engine: engines[0], term: trimmed, score: Score.webFallback)
    }

    private func makeResult(engine: Engine, term: String, score: Double) -> SearchResult {
        SearchResult(
            id: "web:\(engine.prefix)",
            kind: .webSearch,
            title: "\(engine.name)에서 \"\(term)\" 검색",
            subtitle: "웹 검색",
            symbolName: engine.symbol,
            score: score,
            action: { _ in
                let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
                if let url = URL(string: String(format: engine.urlTemplate, encoded)) {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }
}
