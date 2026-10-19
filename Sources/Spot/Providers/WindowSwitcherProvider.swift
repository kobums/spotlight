import AppKit
import ApplicationServices

/// "창전환" / "win"으로 진입하는 창 전환기 — 앱이 아니라 열린 **창** 단위로 검색해
/// Enter로 그 창을 앞으로 가져온다. 최소화된 창도 포함(Enter로 복원).
/// 실행 중인 앱마다 AX 창 목록을 읽어야 해서 비동기 + 캐시(3초).
/// AX는 현재 Space의 창만 돌려주므로 다른 데스크톱의 창은 빠진다.
final class WindowSwitcherProvider {
    private static let keywords = ["창전환", "win"]

    static func isSwitcherQuery(_ query: String) -> Bool {
        let q = query.lowercased()
        return keywords.contains { q == $0 || q.hasPrefix($0 + " ") }
    }

    /// 수집이 비동기라 결과는 항상 콜백으로 전달 (메인 스레드)
    var onResults: (([SearchResult]) -> Void)?

    private struct WindowItem {
        let app: NSRunningApplication
        let appNames: [String]   // 표시 이름이 맨 앞. 현지화 이름·번들 파일명 포함
        let element: AXUIElement
        let title: String
        let minimized: Bool
        let index: Int           // 앱 z-order + 창 순서로 매긴 전체 순서
    }

    private var cached: [WindowItem] = []
    private var cachedAt = Date.distantPast
    private let cacheLifetime: TimeInterval = 3
    private var isCollecting = false
    private var pendingTerm: String?

    func search(_ query: String) {
        guard Self.isSwitcherQuery(query) else { return }
        guard AccessibilityPermission.ensureTrusted() else {
            deliver([])
            return
        }
        let term = query.split(separator: " ", maxSplits: 1)
            .dropFirst().first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""

        if Date().timeIntervalSince(cachedAt) < cacheLifetime {
            deliver(results(matching: term))
            return
        }

        pendingTerm = term
        guard !isCollecting else { return }
        isCollecting = true
        let apps = Self.candidateApps()
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let items = Self.collect(apps)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCollecting = false
                self.cached = items
                self.cachedAt = Date()
                if let pending = self.pendingTerm {
                    self.pendingTerm = nil
                    self.onResults?(self.results(matching: pending))
                }
            }
        }
    }

    /// 항상 다음 런루프에 전달 — syncResults 반환값이 콜백 결과를 덮어쓰지 않게
    private func deliver(_ results: [SearchResult]) {
        DispatchQueue.main.async { [weak self] in
            self?.onResults?(results)
        }
    }

    private func results(matching term: String) -> [SearchResult] {
        let matched: [WindowItem]
        if term.isEmpty {
            matched = cached
        } else {
            matched = cached
                .compactMap { item -> (WindowItem, Double)? in
                    // 창 제목·앱 이름 각각, 그리고 "앱 제목" 결합 문자열로 매칭 ("크롬 깃허브")
                    let haystacks = [item.title] + item.appNames + item.appNames.prefix(1).map { "\($0) \(item.title)" }
                    guard let best = haystacks.compactMap({ FuzzyMatch.score(needle: term, haystack: $0) }).max() else {
                        return nil
                    }
                    return (item, best)
                }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.index < $1.0.index }
                .map { $0.0 }
        }

        guard !matched.isEmpty else {
            return [SearchResult(
                id: "win:none", kind: .window,
                title: cached.isEmpty ? "열린 창 없음" : "일치하는 창 없음",
                subtitle: "현재 데스크톱(Space)의 창만 검색 — 최소화된 창 포함",
                symbolName: "macwindow.on.rectangle", score: 0, action: { _ in })]
        }

        return matched.prefix(50).enumerated().map { rank, item in
            let appName = item.appNames.first ?? ""
            return SearchResult(
                id: "win:\(item.app.processIdentifier):\(item.index)",
                kind: .window,
                title: item.title.isEmpty ? appName : item.title,
                subtitle: item.minimized ? "\(appName) — 최소화됨 · Enter로 복원" : appName,
                icon: item.app.icon,
                symbolName: "macwindow",
                score: -Double(rank), // 전용 모드라 내부 순서만 유지
                action: { _ in Self.focus(item) })
        }
    }

    // MARK: - 수집 (AX)

    /// 창을 가질 수 있는 앱 — Dock에 뜨는 일반 앱만. Spot 자신은 제외.
    /// 앞쪽 창을 가진 앱부터 (CGWindowList의 앞→뒤 순서), 나머지는 이름순
    private static func candidateApps() -> [(NSRunningApplication, [String])] {
        let me = ProcessInfo.processInfo.processIdentifier
        var zOrder: [pid_t: Int] = [:]
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for window in info where (window[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = window[kCGWindowOwnerPID as String] as? pid_t, zOrder[pid] == nil {
                zOrder[pid] = zOrder.count
            }
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != me
        }
        return apps
            .sorted { a, b in
                let za = zOrder[a.processIdentifier] ?? .max, zb = zOrder[b.processIdentifier] ?? .max
                if za != zb { return za < zb }
                return (a.localizedName ?? "").localizedStandardCompare(b.localizedName ?? "") == .orderedAscending
            }
            .map { ($0, names(of: $0)) }
    }

    private static func collect(_ apps: [(NSRunningApplication, [String])]) -> [WindowItem] {
        var visible: [WindowItem] = []
        var minimized: [WindowItem] = []
        var index = 0
        for (app, appNames) in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            // 응답 없는 앱 하나가 전체 수집을 붙잡지 않게
            AXUIElementSetMessagingTimeout(appElement, 0.3)
            for window in AX.windows(of: appElement) {
                let subrole = AX.attribute(window, kAXSubroleAttribute as String) as? String
                // 일반 창·대화상자만 — 팔레트·툴팁·시트 같은 보조 창 제외
                guard subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String else {
                    continue
                }
                let title = (AX.attribute(window, kAXTitleAttribute as String) as? String) ?? ""
                let isMinimized = AX.bool(window, kAXMinimizedAttribute as String)
                let item = WindowItem(app: app, appNames: appNames, element: window,
                                      title: title, minimized: isMinimized, index: index)
                index += 1
                if isMinimized { minimized.append(item) } else { visible.append(item) }
            }
        }
        // 최소화된 창은 목록 끝 — 순서 번호도 그에 맞게 다시 매긴다
        return (visible + minimized).enumerated().map { i, item in
            WindowItem(app: item.app, appNames: item.appNames, element: item.element,
                       title: item.title, minimized: item.minimized, index: i)
        }
    }

    private static func names(of app: NSRunningApplication) -> [String] {
        var candidates: [String] = []
        if let url = app.bundleURL {
            candidates = [app.localizedName].compactMap { $0 }
                + BundleLocalization.localizedNames(bundleURL: url)
                + [(url.lastPathComponent as NSString).deletingPathExtension]
        } else if let name = app.localizedName {
            candidates = [name]
        }
        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - 전환

    private static func focus(_ item: WindowItem) {
        let app = item.app
        if app.isHidden { app.unhide() }
        if item.minimized {
            AXUIElementSetAttributeValue(item.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(item.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)

        // 패널이 비활성 패널이라 Spot은 활성 앱이 아니다 — macOS 14의 협조적 활성화에서도
        // 확실히 앞으로 오도록 NSWorkspace로 활성화한다
        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                // 활성화가 앱의 다른 창을 앞으로 올릴 수 있어 한 번 더 올린다
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)
                }
            }
        } else {
            app.activate(options: [])
        }
        SpotLog.info("창 전환 — \(item.appNames.first ?? "?"): \(item.title)")
    }
}
