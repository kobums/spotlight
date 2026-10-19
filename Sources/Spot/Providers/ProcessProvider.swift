import AppKit

/// 실행 중인 앱 종료: "종료 크롬", "quit slack", "강제종료 ㅋㅋㅇ".
/// Enter = 종료(terminate — 저장 안 한 문서가 있으면 앱이 물어본다), ⌘Enter = 강제 종료.
/// 강제 키워드(`강제종료`, `kill`, `forcequit`)로 들어오면 Enter가 강제 종료다.
///
/// 키워드 `종료`는 시스템 액션 `시스템 종료…`의 키워드이기도 하다. `종료`만 입력했을 때는
/// 그쪽(actionExact)이 최상단이어야 하므로 앱 목록은 그보다 훨씬 낮게 두고, 이 결과는
/// frecency 학습에서도 빼서(.runningApp) 자주 끈 앱이 시스템 종료를 밀어내지 않게 한다.
final class ProcessProvider: SearchProvider {
    private static let quitKeywords = ["종료", "quit", "끝내기"]
    private static let forceKeywords = ["강제종료", "kill", "forcequit"]

    /// 현지화 이름에 없는 한글 음역 별칭 (번들 ID 기준)
    private static let aliases: [String: [String]] = [
        "com.google.Chrome": ["크롬", "구글크롬"],
        "com.apple.Safari": ["사파리"],
        "org.mozilla.firefox": ["파이어폭스"],
        "company.thebrowser.Browser": ["아크"],
        "com.naver.Whale": ["웨일", "네이버웨일"],
        "com.microsoft.edgemac": ["엣지"],
        "com.brave.Browser": ["브레이브"],
        "com.tinyspeck.slackmacgap": ["슬랙"],
        "com.kakao.KakaoTalkMac": ["카카오톡", "카톡"],
        "com.hnc.Discord": ["디스코드"],
        "notion.id": ["노션"],
        "com.spotify.client": ["스포티파이"],
        "com.figma.Desktop": ["피그마"],
        "us.zoom.xos": ["줌"],
        "ru.keepcoder.Telegram": ["텔레그램"],
        "com.microsoft.VSCode": ["vscode", "비주얼스튜디오코드", "코드"],
        "com.todesktop.230313mzl4w4u92": ["커서"],
        "com.docker.docker": ["도커"],
        "com.microsoft.teams2": ["팀즈"],
        "com.microsoft.Word": ["워드"],
        "com.microsoft.Excel": ["엑셀"],
        "com.microsoft.Powerpoint": ["파워포인트"],
    ]

    /// 이름 목록 캐시 — 현지화 이름은 번들 파일을 읽어야 해서 키 입력마다 다시 읽지 않는다
    private var namesCache: [URL: [String]] = [:]

    func results(for query: String) -> [SearchResult] {
        let parts = query.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return [] }
        let quitScore = CommandKeywords.score(first, keywords: Self.quitKeywords)
        let forceScore = CommandKeywords.score(first, keywords: Self.forceKeywords)
        guard let baseScore = [quitScore, forceScore].compactMap({ $0 }).max() else { return [] }
        let force = (forceScore ?? -.infinity) > (quitScore ?? -.infinity)
        let needle = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        // 전체 목록은 키워드를 다 쳤을 때만 — "q"·"k" 한 글자만으로 앱 목록이 쏟아지지 않게
        if needle.isEmpty && baseScore < Score.actionExact { return [] }

        var matches: [(app: NSRunningApplication, name: String, score: Double)] = []
        for app in Self.quittableApps() {
            let names = self.names(of: app)
            guard let title = names.first else { continue }
            if needle.isEmpty {
                matches.append((app, title, 0))   // 0 = 정확 일치 아님
            } else if let best = names.compactMap({ FuzzyMatch.score(needle: needle, haystack: $0) }).max() {
                matches.append((app, title, best))
            }
        }
        // 키워드만 입력 → 이름순 전체 목록, 검색어 있음 → 매칭 점수순
        matches.sort { needle.isEmpty ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.score > $1.score }

        return matches.enumerated().map { rank, match in
            let score: Double
            if match.score.isInfinite {
                score = baseScore + 2                       // "종료 크롬" 정확 일치
            } else {
                // 전체 목록·부분 일치는 다른 명령의 정확 일치보다 아래 —
                // `종료` → 시스템 종료…, `quit spot` → Spot 종료가 최상단에 남는다
                score = baseScore - 1 - Double(rank) * 0.01
            }
            let app = match.app
            let name = match.name
            return SearchResult(
                id: "quit:\(app.bundleIdentifier ?? String(app.processIdentifier))",
                kind: .runningApp,
                title: force ? "\(name) 강제 종료" : "\(name) 종료",
                subtitle: force ? "Enter 강제 종료 (저장하지 않은 내용은 사라짐)" : "Enter 종료 · ⌘Enter 강제 종료",
                icon: app.icon,
                symbolName: "xmark.app",
                score: score,
                action: { modifiers in
                    let forced = force || modifiers.contains(.command)
                    let ok = forced ? app.forceTerminate() : app.terminate()
                    SpotLog.info("앱 \(forced ? "강제 종료" : "종료") 요청 — \(name) (pid \(app.processIdentifier))"
                                 + (ok ? "" : " 실패"))
                })
        }
    }

    /// 종료 대상 — Dock에 뜨는 일반 앱 + 사용자 앱 폴더의 메뉴바 앱. Spot 자신과 Finder는 제외.
    private static func quittableApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        let userAppDirs = ["/Applications/", NSHomeDirectory() + "/Applications/"]
        return NSWorkspace.shared.runningApplications.filter { app in
            // Finder는 terminate를 무시하고 곧바로 다시 뜨므로 목록에서 뺀다
            guard app.processIdentifier != me, !app.isTerminated,
                  app.bundleIdentifier != "com.apple.finder" else { return false }
            switch app.activationPolicy {
            case .regular:
                return true
            case .accessory:
                // 앱 폴더 바로 아래 번들만 — "Brave Browser.app/…/Helper.app" 같은 내부 헬퍼 제외
                let path = app.bundleURL?.path ?? ""
                return userAppDirs.contains { dir in
                    path.hasPrefix(dir) && !path.dropFirst(dir.count).contains(".app/")
                }
            default:
                return false
            }
        }
    }

    /// 표시 이름이 맨 앞. 실행 이름·번들 파일명·현지화 이름·한글 별칭 모두 매칭 대상.
    private func names(of app: NSRunningApplication) -> [String] {
        var candidates: [String] = []
        if let url = app.bundleURL {
            if let cached = namesCache[url] { return cached }
            let localized = BundleLocalization.localizedNames(bundleURL: url)
            candidates = localized + [app.localizedName, (url.lastPathComponent as NSString).deletingPathExtension]
                .compactMap { $0 }
        } else if let name = app.localizedName {
            candidates = [name]
        }
        candidates += Self.aliases[app.bundleIdentifier ?? ""] ?? []
        var seen = Set<String>()
        let names = candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
        if let url = app.bundleURL { namesCache[url] = names }
        return names
    }
}
