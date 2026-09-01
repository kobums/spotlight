import Foundation

/// 프로바이더 결과를 모아 fuzzy 점수 + frecency 부스트로 최종 랭킹.
final class SearchEngine {
    private let fileProvider = FileSearchProvider()
    private let clipboardProvider = ClipboardProvider()
    private let webSearchProvider = WebSearchProvider()
    private let elementProvider = UIElementProvider()
    private let menuProvider = MenuItemProvider()
    private let emojiProvider = EmojiProvider()
    private let tabProvider = TabProvider()

    /// 동기 프로바이더 — 나열 순서가 정렬 전 기본 순서
    private lazy var syncProviders: [SearchProvider] = [
        CalculatorProvider(), webSearchProvider, AppProvider(), SystemSettingsProvider(),
        SystemActionProvider(), AwakeProvider(), DisplayProvider(), InputSourceProvider(),
        BookmarkProvider(), WindowCommandProvider(), SnippetProvider(),
    ]

    /// 파일 검색(비동기) 결과 콜백
    var onFileResults: (([SearchResult]) -> Void)? {
        get { fileProvider.onResults }
        set { fileProvider.onResults = newValue }
    }

    /// UI 요소 검색(비동기) 결과 콜백 — 전용 모드라 기존 결과를 통째로 교체
    var onElementResults: (([SearchResult]) -> Void)? {
        get { elementProvider.onResults }
        set { elementProvider.onResults = newValue }
    }

    /// 메뉴 항목 검색(비동기) 결과 콜백 — 전용 모드라 기존 결과를 통째로 교체
    var onMenuResults: (([SearchResult]) -> Void)? {
        get { menuProvider.onResults }
        set { menuProvider.onResults = newValue }
    }

    /// 브라우저 탭 검색(비동기) 결과 콜백 — 전용 모드라 기존 결과를 통째로 교체
    var onTabResults: (([SearchResult]) -> Void)? {
        get { tabProvider.onResults }
        set { tabProvider.onResults = newValue }
    }

    /// 동기 프로바이더 결과 (즉시 표시)
    func syncResults(for query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            fileProvider.search("")
            return []
        }

        // 클립보드 모드는 전용 결과만
        if ClipboardProvider.isClipboardQuery(trimmed) {
            fileProvider.search("")
            return clipboardProvider.results(for: trimmed)
        }

        // 이모지 모드(":")도 전용
        if EmojiProvider.isEmojiQuery(trimmed) {
            fileProvider.search("")
            return emojiProvider.results(for: trimmed)
        }

        // UI 요소 모드(";")도 전용 — 결과는 onElementResults 콜백으로
        if UIElementProvider.isElementQuery(trimmed) {
            fileProvider.search("")
            elementProvider.search(trimmed)
            return []
        }

        // 메뉴 항목 모드(">")도 전용 — 결과는 onMenuResults 콜백으로
        if MenuItemProvider.isMenuQuery(trimmed) {
            fileProvider.search("")
            menuProvider.search(trimmed)
            return []
        }

        // 브라우저 탭 모드("탭"/"tab")도 전용 — 결과는 onTabResults 콜백으로
        if TabProvider.isTabQuery(trimmed) {
            fileProvider.search("")
            tabProvider.search(trimmed)
            return []
        }

        var results = syncProviders.flatMap { $0.results(for: trimmed) }
        applyFrecencyBoost(to: &results)
        results.sort { $0.score > $1.score }
        appendWebFallbackIfNeeded(to: &results, query: trimmed)
        triggerFileSearchIfNeeded(results, query: trimmed)
        return results
    }

    /// 비동기 파일 결과를 기존 결과에 병합
    func merge(fileResults: [SearchResult], into current: [SearchResult]) -> [SearchResult] {
        guard !fileResults.isEmpty else { return current }
        var merged = current.filter { $0.kind != .file }
        var files = fileResults
        applyFrecencyBoost(to: &files)
        // 웹 폴백은 항상 마지막 유지
        let fallback = merged.last(where: { $0.kind == .webSearch && $0.score < 0 })
        merged.removeAll { $0.kind == .webSearch && $0.score < 0 }
        merged += files
        merged.sort { $0.score > $1.score }
        if let fallback { merged.append(fallback) }
        return merged
    }

    func recordSelection(_ result: SearchResult) {
        // 계산 결과와 UI 요소·브라우저 탭(위치 기반 id라 재현 안 됨)은 학습 대상에서 제외
        guard result.kind != .calculator, result.kind != .uiElement, result.kind != .browserTab else { return }
        FrecencyStore.shared.recordSelection(id: result.id)
    }

    // MARK: - 단계

    private func applyFrecencyBoost(to results: inout [SearchResult]) {
        for i in results.indices {
            results[i].score += FrecencyStore.shared.boost(id: results[i].id) * Score.frecencyWeight
        }
    }

    private func appendWebFallbackIfNeeded(to results: inout [SearchResult], query: String) {
        guard let fallback = webSearchProvider.fallbackResult(for: query),
              !results.contains(where: { $0.kind == .webSearch }) else { return }
        results.append(fallback)
    }

    /// 계산/웹 프리픽스 모드에서는 파일 검색이 소음이라 중단
    private func triggerFileSearchIfNeeded(_ results: [SearchResult], query: String) {
        let suppressed = results.contains { $0.kind == .calculator || ($0.kind == .webSearch && $0.score > 0) }
        fileProvider.search(suppressed ? "" : query)
    }
}
