import AppKit

/// "cb" 또는 "클립" 키워드로 진입하는 클립보드 히스토리 검색.
/// Enter → 클립보드에 복사 (+ 손쉬운 사용 권한이 있으면 자동 붙여넣기)
final class ClipboardProvider {

    static func isClipboardQuery(_ query: String) -> Bool {
        let q = query.lowercased()
        return q == "cb" || q.hasPrefix("cb ") || q == "클립" || q.hasPrefix("클립 ")
    }

    func results(for query: String) -> [SearchResult] {
        guard Self.isClipboardQuery(query) else { return [] }
        let q = query.lowercased()
        let term: String
        if q.hasPrefix("cb ") {
            term = String(query.dropFirst(3))
        } else if q.hasPrefix("클립 ") {
            term = String(query.dropFirst(3))
        } else {
            term = ""
        }

        let entries = ClipboardStore.shared.entries
        let filtered: [ClipboardStore.Entry]
        if term.isEmpty {
            filtered = Array(entries.prefix(30))
        } else {
            filtered = entries.filter {
                $0.text.localizedCaseInsensitiveContains(term)
            }.prefix(30).map { $0 }
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")

        return filtered.enumerated().map { index, entry in
            let preview = entry.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ⏎ ")
            let title = preview.count > 80 ? String(preview.prefix(80)) + "…" : preview
            return SearchResult(
                id: "clip:\(entry.date.timeIntervalSince1970)",
                kind: .clipboard,
                title: title,
                subtitle: formatter.localizedString(for: entry.date, relativeTo: Date()),
                symbolName: "doc.on.clipboard",
                score: 500 - Double(index), // 최신순 유지
                action: { modifiers in
                    ClipboardStore.shared.copyToPasteboard(entry.text)
                    if !modifiers.contains(.option) {
                        Paster.pasteToFrontmostApp()
                    }
                }
            )
        }
    }
}

/// 손쉬운 사용(Accessibility) 권한이 있으면 Cmd+V 이벤트를 합성해 자동 붙여넣기
enum Paster {
    static func pasteToFrontmostApp() {
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
        }
    }
}
