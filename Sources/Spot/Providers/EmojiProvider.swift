import AppKit

/// ":" 접두사로 진입하는 이모지 검색 (":하트", ":smile").
/// Enter → 복사 + 자동 붙여넣기, ⌥Enter → 복사만. 최근 사용한 이모지가 위로 온다.
final class EmojiProvider: SearchProvider {

    static func isEmojiQuery(_ query: String) -> Bool {
        query.hasPrefix(":")
    }

    func results(for query: String) -> [SearchResult] {
        guard Self.isEmojiQuery(query) else { return [] }
        let term = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)

        let matched: [(EmojiCatalog.Entry, Double)]
        if term.isEmpty {
            // 검색어 없으면 최근 사용순(frecency) → 카탈로그 순
            matched = EmojiCatalog.all.map { entry in
                (entry, FrecencyStore.shared.boost(id: "emoji:\(entry.emoji)"))
            }
            .sorted { $0.1 > $1.1 }
        } else {
            matched = EmojiCatalog.all.compactMap { entry in
                let scores = entry.keywords.compactMap {
                    FuzzyMatch.score(needle: term, haystack: $0)
                }
                guard let best = scores.max() else { return nil }
                return (entry, best.isInfinite ? 100 : best)
            }
            .sorted { $0.1 > $1.1 }
        }

        return matched.prefix(30).enumerated().map { index, item in
            let entry = item.0
            return SearchResult(
                id: "emoji:\(entry.emoji)",
                kind: .emoji,
                title: entry.name,
                subtitle: "Enter로 붙여넣기 · ⌥Enter 복사만",
                icon: Self.image(for: entry.emoji),
                score: -Double(index),
                action: { modifiers in
                    ClipboardStore.shared.copy(entry.emoji)
                    if !modifiers.contains(.option) {
                        Paster.pasteToFrontmostApp()
                    }
                }
            )
        }
    }

    // MARK: - 이모지 → 아이콘 이미지

    private static var imageCache: [String: NSImage] = [:]

    private static func image(for emoji: String) -> NSImage {
        if let cached = imageCache[emoji] { return cached }
        let str = NSAttributedString(
            string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 22)])
        let size = str.size()
        let image = NSImage(size: size)
        image.lockFocus()
        str.draw(at: .zero)
        image.unlockFocus()
        imageCache[emoji] = image
        return image
    }
}
