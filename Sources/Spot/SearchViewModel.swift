import AppKit
import Combine

final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [SearchResult] = []
    @Published var selectedIndex: Int = 0

    private let engine = SearchEngine()
    var onExecute: (() -> Void)?  // 실행 후 패널 닫기
    var onDismiss: (() -> Void)?

    init() {
        engine.onFileResults = { [weak self] fileResults in
            guard let self else { return }
            let selectedID = self.results.indices.contains(self.selectedIndex)
                ? self.results[self.selectedIndex].id : nil
            self.results = self.engine.merge(fileResults: fileResults, into: self.results)
            // 사용자가 선택을 옮겨놨으면 그 항목 유지
            if self.selectedIndex > 0, let id = selectedID,
               let newIndex = self.results.firstIndex(where: { $0.id == id }) {
                self.selectedIndex = newIndex
            } else {
                self.selectedIndex = 0
            }
        }
    }

    func queryChanged(_ text: String) {
        query = text
        results = engine.syncResults(for: text)
        selectedIndex = 0
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    func executeSelected(modifiers: NSEvent.ModifierFlags) {
        guard results.indices.contains(selectedIndex) else { return }
        let result = results[selectedIndex]
        engine.recordSelection(result)
        onExecute?()
        result.action(modifiers)
    }

    /// Esc: 쿼리가 있으면 지우고, 없으면 닫기 (Alfred 동작)
    func cancel() {
        if query.isEmpty {
            onDismiss?()
        } else {
            queryChanged("")
        }
    }

    func reset() {
        queryChanged("")
    }
}
