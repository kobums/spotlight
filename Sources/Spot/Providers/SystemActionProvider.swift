import AppKit

/// 시스템 액션: 잠자기, 화면 잠금, 휴지통 비우기, 다크 모드 등.
/// 한글/영문 키워드 모두 fuzzy 매칭.
final class SystemActionProvider {

    private struct Action {
        let id: String
        let title: String
        let keywords: [String]
        let symbol: String
        let run: () -> Void
    }

    private lazy var actions: [Action] = [
        Action(
            id: "action:sleep",
            title: "잠자기",
            keywords: ["sleep", "잠자기", "슬립"],
            symbol: "moon.zzz.fill",
            run: { Self.shell("/usr/bin/pmset", ["sleepnow"]) }
        ),
        Action(
            id: "action:lock",
            title: "화면 잠금",
            keywords: ["lock", "lock screen", "화면잠금", "잠금"],
            symbol: "lock.fill",
            run: {
                Self.shell(
                    "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
                    ["-suspend"]
                )
            }
        ),
        Action(
            id: "action:emptytrash",
            title: "휴지통 비우기",
            keywords: ["empty trash", "trash", "휴지통", "휴지통비우기"],
            symbol: "trash.fill",
            run: { Self.osascript("tell application \"Finder\" to empty trash") }
        ),
        Action(
            id: "action:darkmode",
            title: "다크 모드 전환",
            keywords: ["dark mode", "다크모드", "다크", "라이트모드", "테마"],
            symbol: "circle.lefthalf.filled",
            run: {
                Self.osascript(
                    "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
                )
            }
        ),
        Action(
            id: "action:screensaver",
            title: "화면 보호기",
            keywords: ["screensaver", "화면보호기"],
            symbol: "display",
            run: {
                Self.shell("/usr/bin/open", ["-a", "ScreenSaverEngine"])
            }
        ),
        Action(
            id: "action:restart",
            title: "재시동…",
            keywords: ["restart", "reboot", "재시동", "재부팅"],
            symbol: "arrow.counterclockwise.circle.fill",
            run: { Self.osascript("tell application \"System Events\" to restart") }
        ),
        Action(
            id: "action:shutdown",
            title: "시스템 종료…",
            keywords: ["shutdown", "shut down", "시스템종료", "종료"],
            symbol: "power.circle.fill",
            run: { Self.osascript("tell application \"System Events\" to shut down") }
        ),
        Action(
            id: "action:quit-spot",
            title: "Spot 종료",
            keywords: ["quit spot", "spot 종료"],
            symbol: "xmark.circle.fill",
            run: { NSApp.terminate(nil) }
        ),
    ]

    func results(for query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        var out: [SearchResult] = []
        for action in actions {
            let scores = ([action.title] + action.keywords).compactMap {
                FuzzyMatch.score(needle: query, haystack: $0)
            }
            guard let best = scores.max() else { continue }
            out.append(SearchResult(
                id: action.id,
                kind: .systemAction,
                title: action.title,
                subtitle: "시스템 액션",
                symbolName: action.symbol,
                score: (best.isInfinite ? 50 : best) + 0.5,
                action: { _ in action.run() }
            ))
        }
        return out
    }

    private static func shell(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
    }

    private static func osascript(_ script: String) {
        shell("/usr/bin/osascript", ["-e", script])
    }
}
