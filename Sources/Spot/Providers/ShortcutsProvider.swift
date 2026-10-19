import AppKit

/// macOS 단축어(Shortcuts) 실행: "단축어 아침루틴", "shortcut 밝기".
/// Enter = 실행, ⌘Enter = 단축어 앱에서 편집.
///
/// 목록은 `/usr/bin/shortcuts list --show-identifiers`로 얻어 캐시한다(60초 지나면 백그라운드 갱신).
/// 실행은 `shortcuts run <식별자>` — URL 스킴(`shortcuts://run-shortcut`)은 단축어 앱을 앞으로
/// 띄우고 "Spot이 단축어를 열려고 합니다" 확인이 뜰 수 있지만, CLI는 앱 창 없이 돌고
/// Apple Events가 아니라 자동화 권한 프롬프트도 없다. 단축어 안의 동작이 요구하는 권한은
/// 어느 쪽이든 따로 묻는다.
final class ShortcutsProvider: SearchProvider {
    private static let keywords = ["단축어", "shortcut", "shortcuts"]
    private static let cli = "/usr/bin/shortcuts"
    private static let cacheLifetime: TimeInterval = 60

    private struct Shortcut {
        let name: String
        let identifier: String?
    }

    private var shortcuts: [Shortcut] = []
    private var loadedAt: Date?
    private var isLoading = false

    init() {
        refreshIfNeeded()   // 첫 검색 전에 목록을 받아 둔다
    }

    func results(for query: String) -> [SearchResult] {
        let parts = query.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first,
              let baseScore = CommandKeywords.score(first, keywords: Self.keywords) else { return [] }
        let needle = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        // 전체 목록은 키워드를 다 쳤을 때만 — "단" 한 글자로 목록이 쏟아지지 않게
        if needle.isEmpty && baseScore < Score.actionExact { return [] }
        refreshIfNeeded()

        guard loadedAt != nil else {
            return [infoResult("단축어 목록 불러오는 중…", "잠시 후 다시 입력하세요", score: baseScore)]
        }
        guard !shortcuts.isEmpty else {
            return [infoResult("단축어 없음", "단축어 앱에서 만든 단축어가 여기에 나온다", score: baseScore)]
        }

        var matches: [(shortcut: Shortcut, score: Double)] = []
        for shortcut in shortcuts {
            if needle.isEmpty {
                matches.append((shortcut, 0))
            } else if let score = FuzzyMatch.score(needle: needle, haystack: shortcut.name) {
                matches.append((shortcut, score))
            }
        }
        // 키워드만 입력 → 단축어 앱의 목록 순서 그대로, 검색어 있음 → 매칭 점수순
        if !needle.isEmpty { matches.sort { $0.score > $1.score } }
        guard !matches.isEmpty else {
            return [infoResult("일치하는 단축어 없음", "\"\(needle)\" — 단축어 \(shortcuts.count)개 중", score: baseScore)]
        }

        return matches.prefix(30).enumerated().map { rank, match in
            let shortcut = match.shortcut
            return SearchResult(
                id: "shortcut:\(shortcut.name)",
                kind: .systemAction,
                title: shortcut.name,
                subtitle: "단축어 — Enter 실행 · ⌘Enter 편집",
                icon: Self.appIcon,
                symbolName: "square.stack.3d.up",
                // 이름 정확 일치는 다른 명령의 정확 일치보다 위, 나머지는 그 아래
                score: match.score.isInfinite ? baseScore + 2 : baseScore - 1 - Double(rank) * 0.01,
                action: { modifiers in
                    if modifiers.contains(.command) {
                        Self.openInEditor(shortcut)
                    } else {
                        Self.run(shortcut)
                    }
                })
        }
    }

    private func infoResult(_ title: String, _ subtitle: String, score: Double) -> SearchResult {
        SearchResult(id: "shortcut:info", kind: .systemAction, title: title, subtitle: subtitle,
                     icon: Self.appIcon, symbolName: "square.stack.3d.up", score: score, action: { _ in })
    }

    // MARK: - 목록

    private func refreshIfNeeded() {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < Self.cacheLifetime { return }
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let output = Self.runCLI(["list", "--show-identifiers"])
            let parsed = output.map(Self.parseList)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                // 실패하면 이전 목록 유지, 처음이면 빈 목록으로 확정
                if let parsed {
                    self.shortcuts = parsed
                } else {
                    SpotLog.info("단축어 목록 조회 실패")
                }
                self.loadedAt = Date()
            }
        }
    }

    /// "아침 루틴 (598DADA8-0AD3-45C7-8E67-E98C18B9CF37)" 줄 → 이름 + 식별자.
    /// 이름에 괄호가 들어 있어도 끝의 UUID 괄호만 떼어낸다.
    private static func parseList(_ output: String) -> [Shortcut] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            if let range = text.range(of: #" \(([0-9A-Fa-f-]{36})\)$"#, options: .regularExpression) {
                let id = String(text[range].dropFirst(2).dropLast())
                return Shortcut(name: String(text[..<range.lowerBound]), identifier: id)
            }
            return Shortcut(name: text, identifier: nil)
        }
    }

    // MARK: - 실행

    private static func run(_ shortcut: Shortcut) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 이름이 겹칠 수 있어 식별자 우선
            if runCLI(["run", shortcut.identifier ?? shortcut.name]) != nil {
                SpotLog.info("단축어 실행 — \(shortcut.name)")
            } else if !FileManager.default.isExecutableFile(atPath: cli) {
                // CLI가 없는 환경(매우 드묾)만 URL 스킴으로
                DispatchQueue.main.async { openURL("run-shortcut", shortcut) }
            } else {
                SpotLog.info("단축어 실행 실패 — \(shortcut.name)")
            }
        }
    }

    private static func openInEditor(_ shortcut: Shortcut) {
        openURL("open-shortcut", shortcut)
    }

    private static func openURL(_ action: String, _ shortcut: Shortcut) {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = action
        components.queryItems = [URLQueryItem(name: "name", value: shortcut.name)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    /// shortcuts CLI 실행 — 성공하면 stdout, 실패하면 nil
    private static func runCLI(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static let appIcon: NSImage? = {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }()
}
