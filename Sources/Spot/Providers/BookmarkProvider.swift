import AppKit

/// Chromium 계열 브라우저(Chrome·Whale·Edge·Brave) 북마크 검색.
/// Bookmarks JSON을 읽어 전역 검색에 결과를 섞는다. 파일 mtime이 변할 때만 다시 읽는다.
final class BookmarkProvider: SearchProvider {
    private struct Bookmark {
        let title: String
        let url: URL
        let folder: String
    }

    private var bookmarks: [Bookmark] = []
    private let queue = DispatchQueue(label: "spot.bookmarks", qos: .utility)
    /// queue에서만 접근 — 파일 경로 → 마지막으로 읽은 mtime
    private var mtimes: [String: Date] = [:]

    private static let browserDirs = [
        "Google/Chrome", "Naver/Whale", "Microsoft Edge", "BraveSoftware/Brave-Browser",
    ]

    init() {
        reload()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    func results(for query: String) -> [SearchResult] {
        guard query.count >= 2 else { return [] }
        return bookmarks
            .compactMap { bookmark -> (Bookmark, Double)? in
                let host = bookmark.url.host ?? ""
                let scores = [
                    FuzzyMatch.score(needle: query, haystack: bookmark.title),
                    FuzzyMatch.score(needle: query, haystack: host),
                ].compactMap { $0 }
                guard let best = scores.max() else { return nil }
                return (bookmark, (best.isInfinite ? Score.fileExact : best) + Score.bookmarkPenalty)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { bookmark, score in
                SearchResult(
                    id: "bm:\(bookmark.url.absoluteString)",
                    kind: .bookmark,
                    title: bookmark.title,
                    subtitle: bookmark.url.host ?? bookmark.folder,
                    symbolName: "bookmark.fill",
                    score: score,
                    action: { _ in NSWorkspace.shared.open(bookmark.url) }
                )
            }
    }

    // MARK: - 로드

    private func reload() {
        queue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let files = Self.bookmarkFiles()
            var newMtimes: [String: Date] = [:]
            for file in files {
                newMtimes[file] = (try? fm.attributesOfItem(atPath: file)[.modificationDate]) as? Date
            }
            guard newMtimes != self.mtimes else { return }
            self.mtimes = newMtimes

            var found: [Bookmark] = []
            for file in files {
                guard let data = fm.contents(atPath: file),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let roots = json["roots"] as? [String: Any] else { continue }
                for key in ["bookmark_bar", "other", "synced"] {
                    guard let root = roots[key] as? [String: Any] else { continue }
                    Self.walk(root, folder: "", into: &found)
                }
            }
            // 여러 브라우저·프로필에 같은 URL이 있으면 하나만
            var seen = Set<String>()
            let unique = found.filter { seen.insert($0.url.absoluteString).inserted }
            DispatchQueue.main.async { self.bookmarks = unique }
        }
    }

    private static func bookmarkFiles() -> [String] {
        let fm = FileManager.default
        let base = NSHomeDirectory() + "/Library/Application Support/"
        var files: [String] = []
        for dir in browserDirs {
            let root = base + dir
            guard let profiles = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for profile in profiles where profile == "Default" || profile.hasPrefix("Profile ") {
                let path = root + "/" + profile + "/Bookmarks"
                if fm.fileExists(atPath: path) { files.append(path) }
            }
        }
        return files
    }

    private static func walk(_ node: [String: Any], folder: String, into found: inout [Bookmark]) {
        guard found.count < 20000 else { return }
        let type = node["type"] as? String
        let name = node["name"] as? String ?? ""
        if type == "url" {
            guard let urlString = node["url"] as? String,
                  let url = URL(string: urlString),
                  url.scheme == "http" || url.scheme == "https",
                  !name.isEmpty else { return }
            found.append(Bookmark(title: name, url: url, folder: folder))
        } else if let children = node["children"] as? [[String: Any]] {
            for child in children {
                walk(child, folder: name, into: &found)
            }
        }
    }
}
