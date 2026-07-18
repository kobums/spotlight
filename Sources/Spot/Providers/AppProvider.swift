import AppKit

/// 앱 목록 스캔 + fuzzy 매칭. 시작 시 스캔하고 5분마다 갱신.
final class AppProvider {
    private struct AppEntry {
        let name: String
        let localizedName: String
        let url: URL
    }

    private var apps: [AppEntry] = []
    private let scanQueue = DispatchQueue(label: "spot.appscan", qos: .utility)

    private let searchDirs = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    init() {
        rescan()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.rescan()
        }
    }

    private func rescan() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            var found: [AppEntry] = []
            let fm = FileManager.default
            for dir in self.searchDirs {
                guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for item in items where item.hasSuffix(".app") {
                    let url = URL(fileURLWithPath: dir).appendingPathComponent(item)
                    let name = (item as NSString).deletingPathExtension
                    let localized = (fm.displayName(atPath: url.path) as NSString).deletingPathExtension
                    found.append(AppEntry(name: name, localizedName: localized, url: url))
                }
            }
            // 시스템 설정 등 중요 코어 앱 몇 개 추가
            let extras = ["/System/Library/CoreServices/Finder.app"]
            for path in extras where fm.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                let name = (url.lastPathComponent as NSString).deletingPathExtension
                found.append(AppEntry(name: name, localizedName: fm.displayName(atPath: path), url: url))
            }
            DispatchQueue.main.async { self.apps = found }
        }
    }

    func results(for query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        var out: [SearchResult] = []
        for app in apps {
            let s1 = FuzzyMatch.score(needle: query, haystack: app.name)
            let s2 = FuzzyMatch.score(needle: query, haystack: app.localizedName)
            guard let best = [s1, s2].compactMap({ $0 }).max() else { continue }
            let url = app.url
            out.append(SearchResult(
                id: "app:\(url.path)",
                kind: .app,
                title: app.localizedName,
                icon: NSWorkspace.shared.icon(forFile: url.path),
                score: best.isInfinite ? 100 : best + 2.0, // 앱은 기본 가중치 우대
                action: { _ in
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            ))
        }
        return out
    }

}
