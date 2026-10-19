import AppKit

/// "eden"으로 진입하는 eden 터미널 세션 검색 — `eden list --json`으로 세션을 모아
/// 이름·상태·cwd·마지막 명령을 보여 준다.
/// - Enter = `eden focus <id>` (그 탭을 앞으로), ⌥Enter = 세션 ID 복사
/// - `eden api > make test` = `>` 뒤 텍스트를 `eden send <id>`로 보낸다
///
/// 주의: eden 0.2.1 이하에는 CLI가 없어서 인자를 줘도 GUI가 하나 더 뜬다. 그래서 바이너리를
/// 부르기 전에 반드시 번들 Info.plist 버전(0.2.2 이상)을 확인하고, 확인할 수 없으면 부르지 않는다.
final class EdenProvider {
    static func isEdenQuery(_ query: String) -> Bool {
        let q = query.lowercased()
        return q == "eden" || q.hasPrefix("eden ")
    }

    /// 수집이 비동기라 결과는 항상 콜백으로 전달 (메인 스레드)
    var onResults: (([SearchResult]) -> Void)?

    static let minimumVersion = "0.2.2"

    struct Session: Decodable, Equatable {
        let id: UInt64
        let pid: Int
        let cols: Int
        let lines: Int
        let running: Bool
        let lastExit: Int?
        let cwd: String
        let command: String
        let commands: UInt64
        let completions: UInt64
        let name: String?

        enum CodingKeys: String, CodingKey {
            case id, pid, cols, lines, running, cwd, command, commands, completions, name
            case lastExit = "last_exit"
        }
    }

    /// 쿼리 해석 결과 — "eden api > make test" → term "api", sendText "make test"
    struct ParsedQuery: Equatable {
        let term: String
        let sendText: String?
    }

    private var cached: [Session] = []
    private var cachedAt = Date.distantPast
    private let cacheLifetime: TimeInterval = 2
    private var isCollecting = false
    private var pendingQuery: ParsedQuery?

    func search(_ query: String) {
        guard Self.isEdenQuery(query) else { return }
        let parsed = Self.parse(query)

        let binary: URL
        switch Self.resolveBinary() {
        case .success(let url):
            binary = url
        case .failure(let problem):
            deliver([problemResult(problem), openAppResult(score: -1)])
            return
        }

        if Date().timeIntervalSince(cachedAt) < cacheLifetime {
            deliver(results(for: parsed))
            return
        }

        pendingQuery = parsed
        guard !isCollecting else { return }
        isCollecting = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = Self.run(binary, ["list", "--json"])
            let sessions = output.flatMap { Self.parseSessions(Data($0.utf8)) }
            if sessions == nil { SpotLog.info("eden list --json 실패") }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCollecting = false
                self.cached = sessions ?? []
                self.cachedAt = Date()
                if let pending = self.pendingQuery {
                    self.pendingQuery = nil
                    self.onResults?(self.results(for: pending))
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

    // MARK: - 쿼리·JSON (순수 함수)

    static func parse(_ query: String) -> ParsedQuery {
        let body = query.dropFirst(4)   // "eden"
        guard let arrow = body.firstIndex(of: ">") else {
            return ParsedQuery(term: body.trimmingCharacters(in: .whitespaces), sendText: nil)
        }
        let term = body[..<arrow].trimmingCharacters(in: .whitespaces)
        let text = body[body.index(after: arrow)...].trimmingCharacters(in: .whitespaces)
        return ParsedQuery(term: term, sendText: text)
    }

    static func parseSessions(_ data: Data) -> [Session]? {
        try? JSONDecoder().decode([Session].self, from: data)
    }

    /// 매칭 대상 — 이름, cwd 마지막 폴더, ~ 축약 cwd, 명령, ID
    static func matchScore(_ term: String, _ session: Session) -> Double? {
        if term == String(session.id) || term == "#\(session.id)" { return .infinity }
        let haystacks = [session.name ?? "", (session.cwd as NSString).lastPathComponent,
                         abbreviateHome(session.cwd), session.command]
        return haystacks.filter { !$0.isEmpty }
            .compactMap { FuzzyMatch.score(needle: term, haystack: $0) }
            .max()
    }

    static func versionAtLeast(_ version: String, _ minimum: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let b = minimum.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return true
    }

    private static func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - 결과

    private func results(for query: ParsedQuery) -> [SearchResult] {
        var matched: [Session]
        if query.term.isEmpty {
            matched = cached.sorted { $0.id < $1.id }
        } else {
            matched = cached
                .compactMap { session in Self.matchScore(query.term, session).map { (session, $0) } }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }
                .map(\.0)
        }

        if let text = query.sendText {
            guard !text.isEmpty else {
                return [infoResult("보낼 명령을 입력하세요", "eden \(query.term) > make test — Enter로 세션에 입력")]
            }
            guard !matched.isEmpty else {
                return [infoResult(cached.isEmpty ? "eden 세션 없음" : "일치하는 세션 없음",
                                   "\"\(query.term)\"에 보낼 수 없음")]
            }
            return matched.prefix(20).enumerated().map { rank, session in
                sendResult(session, text: text, score: -Double(rank))
            }
        }

        var results = matched.prefix(30).enumerated().map { rank, session in
            sessionResult(session, score: -Double(rank))
        }
        if results.isEmpty {
            results.append(infoResult(cached.isEmpty ? "eden 세션 없음" : "일치하는 세션 없음",
                                      cached.isEmpty ? "eden이 실행 중이 아니거나 열린 탭이 없다"
                                                     : "이름·폴더·명령·ID로 검색"))
        }
        // `eden`만 입력했으면 앱 실행 행도 — 앱 검색을 이 모드가 가로채므로
        if query.term.isEmpty {
            results.append(openAppResult(score: -1000))
        }
        return results
    }

    private static func title(_ session: Session) -> String {
        if let name = session.name, !name.isEmpty { return "\(name)  #\(session.id)" }
        return "\((session.cwd as NSString).lastPathComponent)  #\(session.id)"
    }

    private static func state(_ session: Session) -> String {
        if session.running {
            return session.command.isEmpty ? "실행 중" : "실행 중: \(session.command)"
        }
        guard !session.command.isEmpty else { return "대기" }
        let exit = session.lastExit.map { $0 == 0 ? "✓" : "✗ \($0)" } ?? ""
        return "대기 · 마지막 \(session.command) \(exit)".trimmingCharacters(in: .whitespaces)
    }

    private func sessionResult(_ session: Session, score: Double) -> SearchResult {
        SearchResult(
            id: "eden:\(session.id)",
            kind: .edenSession,
            title: Self.title(session),
            subtitle: "\(Self.state(session)) — \(Self.abbreviateHome(session.cwd)) · ⏎ 포커스 · ⌥⏎ ID 복사",
            icon: Self.appIcon,
            symbolName: session.running ? "terminal.fill" : "terminal",
            score: score,
            action: { modifiers in
                if modifiers.contains(.option) {
                    ClipboardStore.shared.copy(String(session.id))
                } else {
                    Self.invoke(["focus", String(session.id)], activate: true)
                }
            })
    }

    private func sendResult(_ session: Session, text: String, score: Double) -> SearchResult {
        SearchResult(
            id: "eden:send:\(session.id)",
            kind: .edenSession,
            title: "\(Self.title(session))에 보내기: \(text)",
            subtitle: "\(Self.state(session)) — \(Self.abbreviateHome(session.cwd)) · ⏎ 보내기 · ⌥⏎ ID 복사",
            icon: Self.appIcon,
            symbolName: "paperplane",
            score: score,
            action: { modifiers in
                if modifiers.contains(.option) {
                    ClipboardStore.shared.copy(String(session.id))
                } else {
                    // `--` 뒤는 옵션 해석 없이 그대로 텍스트 (`-n` 같은 단어도 안전)
                    Self.invoke(["send", String(session.id), "--", text], activate: false)
                }
            })
    }

    private func infoResult(_ title: String, _ subtitle: String) -> SearchResult {
        SearchResult(id: "eden:info", kind: .edenSession, title: title, subtitle: subtitle,
                     icon: Self.appIcon, symbolName: "terminal", score: 0, action: { _ in })
    }

    private func problemResult(_ problem: BinaryProblem) -> SearchResult {
        let subtitle: String
        switch problem {
        case .notInstalled:
            subtitle = "eden.app을 찾을 수 없음 — brew install --cask kobums/tap/eden"
        case .tooOld(let version):
            subtitle = "설치된 eden \(version)에는 세션 CLI(list·focus·send)가 없다 — brew upgrade --cask eden"
        case .unverifiable(let path):
            subtitle = "\(path) — 앱 번들 밖이라 버전을 확인할 수 없어 실행하지 않음"
        }
        return SearchResult(id: "eden:version", kind: .edenSession,
                            title: "eden \(Self.minimumVersion) 이상 필요", subtitle: subtitle,
                            icon: Self.appIcon, symbolName: "exclamationmark.triangle", score: 0, action: { _ in })
    }

    private func openAppResult(score: Double) -> SearchResult {
        SearchResult(id: "eden:open", kind: .edenSession, title: "eden 열기", subtitle: "eden 터미널 앱 실행",
                     icon: Self.appIcon, symbolName: "terminal", score: score,
                     action: { _ in Self.activateApp() })
    }

    // MARK: - 바이너리

    enum BinaryProblem: Error {
        case notInstalled
        case tooOld(String)
        case unverifiable(String)
    }

    private static let appBundlePaths = ["/Applications/eden.app", NSHomeDirectory() + "/Applications/eden.app"]

    /// /Applications의 앱 번들 바이너리 우선, 없으면 PATH의 `eden`(Homebrew 심볼릭 링크)을 따라가
    /// 그 번들을 찾는다. 어느 쪽이든 번들 Info.plist 버전이 0.2.2 이상일 때만 돌려준다.
    static func resolveBinary() -> Result<URL, BinaryProblem> {
        var bundles = appBundlePaths.filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        var unbundled: String?
        if bundles.isEmpty, let onPath = pathBinary() {
            let real = onPath.resolvingSymlinksInPath()
            if let bundle = enclosingBundle(real) {
                bundles.append(bundle)
            } else {
                unbundled = onPath.path
            }
        }
        guard let bundle = bundles.first else {
            return .failure(unbundled.map { .unverifiable($0) } ?? .notInstalled)
        }
        // Bundle(url:)은 Info.plist를 프로세스 안에 캐시해 업그레이드를 못 본다 — 매번 파일에서 읽는다
        let version = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
        guard let version else { return .failure(.unverifiable(bundle.path)) }
        guard versionAtLeast(version, minimumVersion) else { return .failure(.tooOld(version)) }
        let binary = bundle.appendingPathComponent("Contents/MacOS/eden")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { return .failure(.notInstalled) }
        return .success(binary)
    }

    /// GUI 앱의 PATH는 /usr/bin:/bin 정도라 Homebrew 경로를 덧붙여 찾는다
    private static func pathBinary() -> URL? {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = envPath.split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.cargo/bin"]
        return dirs.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent("eden") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func enclosingBundle(_ url: URL) -> URL? {
        var current = url
        while current.path != "/" {
            if current.pathExtension == "app" { return current }
            current.deleteLastPathComponent()
        }
        return nil
    }

    // MARK: - 실행

    /// focus·send — 결과를 기다리지 않는 명령. 실행 직전에 버전을 다시 확인한다.
    private static func invoke(_ arguments: [String], activate: Bool) {
        guard case .success(let binary) = resolveBinary() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = run(binary, arguments, captureOutput: false) != nil
            SpotLog.info("eden \(arguments.joined(separator: " "))" + (ok ? "" : " 실패"))
            // focus는 GUI가 탭을 앞으로 올리지만, 비활성 패널에서 부른 것이라 앱 활성화를 보장한다
            if ok && activate { DispatchQueue.main.async { activateApp() } }
        }
    }

    private static func activateApp() {
        guard let bundle = appBundlePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundle), configuration: config)
    }

    /// 성공(종료 코드 0)하면 stdout(captureOutput이 false면 빈 문자열), 실패·시간 초과면 nil.
    /// focus·send는 출력을 받지 않는다 — 자식(GUI 실행용 open 등)이 파이프를 물고 있으면
    /// EOF가 오지 않아 읽기가 끝나지 않을 수 있어서다.
    private static func run(_ binary: URL, _ arguments: [String], captureOutput: Bool = true) -> String? {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = captureOutput ? pipe : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        // focus는 GUI가 없으면 띄우고 최대 5초 기다린다
        DispatchQueue.global().asyncAfter(deadline: .now() + (arguments.first == "focus" ? 7 : 3), execute: timeout)
        let data = captureOutput ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static let appIcon: NSImage? = {
        guard let bundle = appBundlePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        return NSWorkspace.shared.icon(forFile: bundle)
    }()
}
