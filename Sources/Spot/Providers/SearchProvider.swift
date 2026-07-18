/// 동기 검색 프로바이더 공통 인터페이스.
/// 쿼리가 자기 담당이 아니면 빈 배열을 돌려준다.
protocol SearchProvider {
    func results(for query: String) -> [SearchResult]
}
