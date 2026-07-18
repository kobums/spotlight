import Foundation

/// 프로바이더 결과를 모아 fuzzy 점수 + frecency 부스트로 최종 랭킹.
final class SearchEngine {
    private let appProvider = AppProvider()
    private let fileProvider = FileSearchProvider()
    private let calculatorProvider = CalculatorProvider()
    private let clipboardProvider = ClipboardProvider()
    private let systemActionProvider = SystemActionProvider()
    private let webSearchProvider = WebSearchProvider()

    /// 파일 검색(비동기) 결과 콜백
    var onFileResults: (([SearchResult]) -> Void)? {
        get { fileProvider.onResults }
        set { fileProvider.onResults = newValue }
    }

    /// 동기 프로바이더 결과 (즉시 표시)
    func syncResults(for query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            fileProvider.search("")
            return appProvider.frequentApps(limit: 8)
        }

        // 클립보드 모드는 전용 결과만
        if ClipboardProvider.isClipboardQuery(trimmed) {
            fileProvider.search("")
            return clipboardProvider.results(for: trimmed)
        }

        var results: [SearchResult] = []
        results += calculatorProvider.results(for: trimmed)
        results += webSearchProvider.prefixResults(for: trimmed)
        results += appProvider.results(for: trimmed)
        results += systemActionProvider.results(for: trimmed)

        // frecency 부스트 적용
        for i in results.indices {
            results[i].score += FrecencyStore.shared.boost(id: results[i].id) * 2.0
        }
        results.sort { $0.score > $1.score }

        if let fallback = webSearchProvider.fallbackResult(for: trimmed),
           !results.contains(where: { $0.kind == .webSearch }) {
            results.append(fallback)
        }

        // 파일 검색은 백그라운드로 (클립보드/계산/웹 프리픽스 모드가 아닐 때만)
        if results.first(where: { $0.kind == .calculator || ($0.kind == .webSearch && $0.score > 0) }) == nil {
            fileProvider.search(trimmed)
        } else {
            fileProvider.search("")
        }

        return results
    }

    /// 비동기 파일 결과를 기존 결과에 병합
    func merge(fileResults: [SearchResult], into current: [SearchResult]) -> [SearchResult] {
        guard !fileResults.isEmpty else { return current }
        var merged = current.filter { $0.kind != .file }
        var files = fileResults
        for i in files.indices {
            files[i].score += FrecencyStore.shared.boost(id: files[i].id) * 2.0
        }
        // 웹 폴백은 항상 마지막 유지
        let fallback = merged.last(where: { $0.kind == .webSearch && $0.score < 0 })
        merged.removeAll { $0.kind == .webSearch && $0.score < 0 }
        merged += files
        merged.sort { $0.score > $1.score }
        if let fallback { merged.append(fallback) }
        return merged
    }

    func recordSelection(_ result: SearchResult) {
        // 계산 결과나 웹 폴백은 학습 대상에서 제외
        guard result.kind != .calculator else { return }
        FrecencyStore.shared.recordSelection(id: result.id)
    }
}
