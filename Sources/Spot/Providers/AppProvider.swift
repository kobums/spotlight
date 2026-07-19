import AppKit

/// 앱 목록 스캔 + fuzzy 매칭. 시작 시 스캔하고 5분마다 갱신.
///
/// FileManager.displayName은 Spot 번들이 해당 언어를 선언하지 않으면 영어 이름만
/// 돌려주므로, 번들의 InfoPlist.loctable(신형식)·<lang>.lproj/InfoPlist.strings(구형식)를
/// 직접 읽어 사용자 언어 이름까지 검색 대상에 넣는다. ("음악"으로 Music 검색 가능)
final class AppProvider: SearchProvider {
    private struct AppEntry {
        let title: String     // 표시 이름 (사용자 언어 우선)
        let names: [String]   // fuzzy 매칭 대상 (영/한 모두)
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

    /// 현지화 이름으로는 안 잡히는 익숙한 별칭
    private static let aliases: [String: [String]] = [
        "System Settings": ["환경설정", "시스템 환경설정", "preferences"],
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
                    found.append(Self.makeEntry(url: URL(fileURLWithPath: dir).appendingPathComponent(item)))
                }
            }
            // 시스템 설정 등 중요 코어 앱 몇 개 추가
            let extras = ["/System/Library/CoreServices/Finder.app"]
            for path in extras where fm.fileExists(atPath: path) {
                found.append(Self.makeEntry(url: URL(fileURLWithPath: path)))
            }
            DispatchQueue.main.async { self.apps = found }
        }
    }

    func results(for query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        var out: [SearchResult] = []
        for app in apps {
            let scores = app.names.compactMap { FuzzyMatch.score(needle: query, haystack: $0) }
            guard let best = scores.max() else { continue }
            let url = app.url
            out.append(SearchResult(
                id: "app:\(url.path)",
                kind: .app,
                title: app.title,
                icon: NSWorkspace.shared.icon(forFile: url.path),
                score: best.isInfinite ? Score.appExact : best + Score.appBonus,
                action: { _ in
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            ))
        }
        return out
    }

    // MARK: - 이름 수집

    private static func makeEntry(url: URL) -> AppEntry {
        let fm = FileManager.default
        let baseName = (url.lastPathComponent as NSString).deletingPathExtension
        let displayName = (fm.displayName(atPath: url.path) as NSString).deletingPathExtension
        let localized = BundleLocalization.localizedNames(bundleURL: url)

        var seen = Set<String>()
        let names = ([baseName, displayName] + localized + (aliases[baseName] ?? []))
            .filter { seen.insert($0).inserted }
        return AppEntry(title: localized.first ?? displayName, names: names, url: url)
    }

}
