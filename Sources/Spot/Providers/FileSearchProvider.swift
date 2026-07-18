import AppKit

/// Spotlight 인덱스(NSMetadataQuery) 재사용 — Raycast/Alfred와 같은 방식.
/// 250ms 디바운스 후 홈 디렉터리 스코프로 파일명 검색.
final class FileSearchProvider {
    private var query: NSMetadataQuery?
    private var debounceTimer: Timer?
    private var observer: NSObjectProtocol?

    var onResults: (([SearchResult]) -> Void)?

    func search(_ text: String) {
        debounceTimer?.invalidate()
        stop()
        guard text.count >= 3 else { return }
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.start(text)
        }
    }

    func stop() {
        if let q = query {
            q.stop()
            query = nil
        }
        if let o = observer {
            NotificationCenter.default.removeObserver(o)
            observer = nil
        }
    }

    private func start(_ text: String) {
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", text)
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]

        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: q,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            q.disableUpdates()
            var results: [SearchResult] = []
            let excluded = ["/Library/", "/node_modules/", "/.git/", "/.build/", "/DerivedData/"]
            let count = q.resultCount
            var taken = 0
            for i in 0..<count {
                guard taken < 20 else { break }
                guard let item = q.result(at: i) as? NSMetadataItem,
                      let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                if excluded.contains(where: { path.contains($0) }) { continue }
                let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                    ?? (path as NSString).lastPathComponent
                let fuzzy = FuzzyMatch.score(needle: text, haystack: name) ?? 0
                let url = URL(fileURLWithPath: path)
                results.append(SearchResult(
                    id: "file:\(path)",
                    kind: .file,
                    title: name,
                    subtitle: shortenPath(path),
                    icon: NSWorkspace.shared.icon(forFile: path),
                    score: (fuzzy.isInfinite ? Score.fileExact : fuzzy) + Score.filePenalty,
                    action: { modifiers in
                        if modifiers.contains(.option) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            NSWorkspace.shared.open(url)
                        }
                    }
                ))
                taken += 1
            }
            self.stop()
            self.onResults?(results)
        }
        query = q
        q.start()
    }

    private func shortenPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
