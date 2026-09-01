import Foundation

/// 키워드 → 자주 쓰는 문구 저장소. snippets.json에 영속.
/// 키워드는 유일 — 같은 키워드로 추가하면 덮어쓴다.
final class SnippetStore {
    static let shared = SnippetStore()

    struct Snippet: Codable {
        let keyword: String
        let text: String
        let date: Date
    }

    private(set) var snippets: [Snippet] = []
    private let store = JSONFileStore<[Snippet]>(filename: "snippets.json", saveDelay: 1.0)

    private init() {
        snippets = store.load() ?? []
    }

    func add(keyword: String, text: String) {
        snippets.removeAll { $0.keyword == keyword }
        snippets.insert(Snippet(keyword: keyword, text: text, date: Date()), at: 0)
        store.scheduleSave(snippets)
    }

    func remove(keyword: String) {
        snippets.removeAll { $0.keyword == keyword }
        store.scheduleSave(snippets)
    }
}
