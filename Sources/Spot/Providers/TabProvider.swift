import AppKit

/// "탭" 키워드로 진입하는 열린 브라우저 탭 검색.
/// 실행 중인 브라우저(Chrome·Whale·Edge·Brave·Safari)의 탭을 osascript(JXA)로
/// 수집하고, Enter로 해당 탭을 활성화한다. 첫 사용 시 브라우저별 자동화(Automation)
/// 권한 프롬프트가 뜬다. 수집이 느릴 수 있어 비동기 + 캐시(5초).
final class TabProvider {
    static func isTabQuery(_ query: String) -> Bool {
        let q = query.lowercased()
        return ["탭", "tab", "tabs"].contains(q)
            || q.hasPrefix("탭 ") || q.hasPrefix("tab ") || q.hasPrefix("tabs ")
    }

    /// 수집이 비동기라 결과는 항상 콜백으로 전달 (메인 스레드)
    var onResults: (([SearchResult]) -> Void)?

    private struct Browser {
        let bundleID: String
        let name: String
        let isSafari: Bool
    }

    private static let browsers = [
        Browser(bundleID: "com.google.Chrome", name: "Chrome", isSafari: false),
        Browser(bundleID: "com.naver.whale", name: "Whale", isSafari: false),
        Browser(bundleID: "com.microsoft.edgemac", name: "Edge", isSafari: false),
        Browser(bundleID: "com.brave.Browser", name: "Brave", isSafari: false),
        Browser(bundleID: "com.apple.Safari", name: "Safari", isSafari: true),
    ]

    private struct Tab {
        let browser: Browser
        let windowIndex: Int
        let tabIndex: Int
        let title: String
        let url: String
    }

    private var cached: [Tab] = []
    private var cachedAt = Date.distantPast
    private let cacheLifetime: TimeInterval = 5
    private var isCollecting = false
    private var pendingTerm: String?

    func search(_ query: String) {
        guard Self.isTabQuery(query) else { return }
        let term = query.split(separator: " ", maxSplits: 1)
            .dropFirst().first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""

        if Date().timeIntervalSince(cachedAt) < cacheLifetime {
            deliver(results(matching: term))
            return
        }

        pendingTerm = term
        guard !isCollecting else { return }
        isCollecting = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tabs = Self.collect()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCollecting = false
                self.cached = tabs
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
        let matched: [Tab]
        if term.isEmpty {
            matched = Array(cached.prefix(30))
        } else {
            matched = cached
                .compactMap { tab -> (Tab, Double)? in
                    let host = URL(string: tab.url)?.host ?? ""
                    let scores = [
                        FuzzyMatch.score(needle: term, haystack: tab.title),
                        FuzzyMatch.score(needle: term, haystack: host),
                    ].compactMap { $0 }
                    guard let best = scores.max() else { return nil }
                    return (tab, best)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(30)
                .map { $0.0 }
        }

        guard !matched.isEmpty else {
            let anyRunning = Self.browsers.contains { Self.isRunning($0) }
            return [SearchResult(
                id: "tab:none",
                kind: .browserTab,
                title: anyRunning ? "일치하는 탭 없음" : "실행 중인 브라우저 없음",
                subtitle: "Chrome · Whale · Edge · Brave · Safari 지원",
                symbolName: "macwindow",
                score: 0,
                action: { _ in }
            )]
        }

        return matched.enumerated().map { index, tab in
            SearchResult(
                id: "tab:\(tab.browser.bundleID):\(tab.windowIndex):\(tab.tabIndex)",
                kind: .browserTab,
                title: tab.title.isEmpty ? tab.url : tab.title,
                subtitle: "\(tab.browser.name) — \(URL(string: tab.url)?.host ?? tab.url)",
                icon: Self.appIcon(bundleID: tab.browser.bundleID),
                symbolName: "macwindow",
                score: -Double(index), // 전용 모드라 내부 순서만 유지
                action: { _ in Self.activate(tab) }
            )
        }
    }

    // MARK: - 수집 (JXA)

    private static func collect() -> [Tab] {
        var tabs: [Tab] = []
        for browser in browsers where isRunning(browser) {
            let titleProp = browser.isSafari ? "name" : "title"
            let script = """
            (() => {
              const app = Application("\(browser.bundleID)");
              const out = [];
              const wins = app.windows;
              for (let w = 0; w < wins.length; w++) {
                let winTabs;
                try { winTabs = wins[w].tabs; } catch (e) { continue; }
                for (let t = 0; t < winTabs.length; t++) {
                  try {
                    out.push([w, t, String(winTabs[t].\(titleProp)() || ""), String(winTabs[t].url() || "")]);
                  } catch (e) {}
                }
              }
              return JSON.stringify(out);
            })()
            """
            guard let output = runJXA(script),
                  let data = output.data(using: .utf8),
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { continue }
            for row in rows {
                guard row.count == 4,
                      let w = row[0] as? Int, let t = row[1] as? Int,
                      let title = row[2] as? String, let url = row[3] as? String else { continue }
                tabs.append(Tab(browser: browser, windowIndex: w, tabIndex: t, title: title, url: url))
            }
        }
        return tabs
    }

    private static func activate(_ tab: Tab) {
        let select = tab.browser.isSafari
            ? "win.currentTab = win.tabs[\(tab.tabIndex)];"
            : "win.activeTabIndex = \(tab.tabIndex + 1);"
        let script = """
        (() => {
          const app = Application("\(tab.browser.bundleID)");
          const win = app.windows[\(tab.windowIndex)];
          \(select)
          win.index = 1;
          app.activate();
        })()
        """
        DispatchQueue.global(qos: .userInitiated).async {
            _ = runJXA(script)
        }
    }

    private static func isRunning(_ browser: Browser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    private static func appIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// osascript -l JavaScript 실행 결과 (stdout, 실패 시 nil)
    private static func runJXA(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
