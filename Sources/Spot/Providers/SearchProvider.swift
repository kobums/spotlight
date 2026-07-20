/// 동기 검색 프로바이더 공통 인터페이스.
/// 쿼리가 자기 담당이 아니면 빈 배열을 돌려준다.
protocol SearchProvider {
    func results(for query: String) -> [SearchResult]
}

/// 명령형 프로바이더(awake·밝기·입력규칙 …)의 키워드 매칭 공통 로직.
/// 첫 토큰을 키워드들과 fuzzy 매칭해 액션 티어 점수로 변환한다.
enum CommandKeywords {
    static func score(_ token: String, keywords: [String]) -> Double? {
        let scores = keywords.compactMap { FuzzyMatch.score(needle: token, haystack: $0) }
        guard let best = scores.max() else { return nil }
        return (best.isInfinite ? Score.actionExact : best) + Score.actionBonus
    }
}
