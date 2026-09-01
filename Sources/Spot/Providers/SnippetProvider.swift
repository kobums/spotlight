import AppKit

/// 스니펫 검색·관리.
/// - 전역 검색: 등록된 키워드가 fuzzy 매칭되면 결과에 섞인다 — Enter 붙여넣기, ⌥Enter 복사만
/// - `스니펫`: 전체 목록 (⌘Enter = 삭제)
/// - `스니펫 추가 <키워드> <내용>`: 등록. 내용을 생략하면 현재 클립보드 텍스트로 저장
final class SnippetProvider: SearchProvider {
    private static let keywords = ["스니펫", "snippet", "snip"]
    private static let addKeywords = ["추가", "add"]

    func results(for query: String) -> [SearchResult] {
        let parts = query.split(separator: " ", maxSplits: 1)
        guard let first = parts.first else { return [] }
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        // "스니펫 …" 명령 모드
        if let baseScore = CommandKeywords.score(String(first), keywords: Self.keywords) {
            if let addResult = addResult(rest: rest, score: baseScore + 2) {
                return [addResult]
            }
            return listResults(term: rest, baseScore: baseScore)
        }

        // 전역 검색 — 키워드 직접 매칭
        return SnippetStore.shared.snippets.compactMap { snippet in
            guard let score = FuzzyMatch.score(needle: query, haystack: snippet.keyword) else { return nil }
            return result(for: snippet,
                          score: (score.isInfinite ? Score.actionExact : score) + Score.actionBonus)
        }
    }

    /// "추가 <키워드> [내용]" 파싱 — 담당 아니면 nil
    private func addResult(rest: String, score: Double) -> SearchResult? {
        let parts = rest.split(separator: " ", maxSplits: 2)
        guard let command = parts.first,
              Self.addKeywords.contains(String(command).lowercased()) else { return nil }
        guard parts.count >= 2 else {
            return SearchResult(
                id: "snippet:add",
                kind: .snippet,
                title: "스니펫 추가",
                subtitle: "스니펫 추가 <키워드> <내용> — 내용 생략 시 클립보드에서",
                symbolName: "plus.square.on.square",
                score: score,
                action: { _ in }
            )
        }
        let keyword = String(parts[1])
        let inline = parts.count > 2 ? String(parts[2]) : ""
        let fromClipboard = inline.isEmpty
        let text = fromClipboard ? (NSPasteboard.general.string(forType: .string) ?? "") : inline
        guard !text.isEmpty else { return nil }

        let preview = text.replacingOccurrences(of: "\n", with: " ⏎ ")
        return SearchResult(
            id: "snippet:add:\(keyword)",
            kind: .snippet,
            title: "스니펫 추가: \(keyword)",
            subtitle: fromClipboard ? "클립보드 내용으로 저장 — \(preview.prefix(60))" : String(preview.prefix(80)),
            symbolName: "plus.square.on.square",
            score: score,
            action: { _ in SnippetStore.shared.add(keyword: keyword, text: text) }
        )
    }

    private func listResults(term: String, baseScore: Double) -> [SearchResult] {
        let snippets = SnippetStore.shared.snippets
        guard !snippets.isEmpty else {
            return [SearchResult(
                id: "snippet:empty",
                kind: .snippet,
                title: "등록된 스니펫 없음",
                subtitle: "스니펫 추가 <키워드> <내용> 으로 등록",
                symbolName: "square.on.square",
                score: baseScore,
                action: { _ in }
            )]
        }
        let filtered: [SnippetStore.Snippet]
        if term.isEmpty {
            filtered = snippets
        } else {
            filtered = snippets
                .compactMap { snippet -> (SnippetStore.Snippet, Double)? in
                    let scores = [
                        FuzzyMatch.score(needle: term, haystack: snippet.keyword),
                        FuzzyMatch.score(needle: term, haystack: snippet.text),
                    ].compactMap { $0 }
                    guard let best = scores.max() else { return nil }
                    return (snippet, best)
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        }
        return filtered.enumerated().map { index, snippet in
            result(for: snippet, score: baseScore - Double(index) * 0.01)
        }
    }

    private func result(for snippet: SnippetStore.Snippet, score: Double) -> SearchResult {
        let preview = snippet.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        return SearchResult(
            id: "snippet:\(snippet.keyword)",
            kind: .snippet,
            title: snippet.keyword,
            subtitle: "스니펫 — \(preview.prefix(70))",
            symbolName: "square.on.square",
            score: score,
            action: { modifiers in
                // ⌘Enter → 삭제
                if modifiers.contains(.command) {
                    SnippetStore.shared.remove(keyword: snippet.keyword)
                    return
                }
                ClipboardStore.shared.copy(snippet.text)
                if !modifiers.contains(.option) {
                    Paster.pasteToFrontmostApp()
                }
            }
        )
    }
}
