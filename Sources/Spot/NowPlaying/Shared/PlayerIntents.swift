import AppIntents

// 위젯 버튼이 실행하는 동작. 실제 제어는 앱이 한다 (`PlayerCommand` 참고).
//
// 이 파일은 앱과 위젯 확장 두 타깃에 모두 들어가야 한다. 시스템은 버튼의 인텐트를 앱 번들 이름으로 찾기 때문에,
// 위젯 확장에만 있으면 "Missing: com.gowoobro.spot.nowplaying:PlayPauseIntent"가 되어 눌러도 실행되지 않는다.

struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "재생/일시 정지"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await PlayerCommand.playPause.send()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "다음 곡"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await PlayerCommand.next.send()
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "이전 곡"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await PlayerCommand.previous.send()
        return .result()
    }
}

/// 진행 막대의 한 칸을 눌렀을 때: 그 위치로 옮긴다.
struct SeekIntent: AppIntent {
    static let title: LocalizedStringResource = "재생 위치 옮기기"
    static let isDiscoverable = false

    /// 곡 길이에 대한 비율(0…1).
    @Parameter(title: "위치", default: 0, inclusiveRange: (0, 1))
    var fraction: Double

    /// 위젯이 그리고 있던 곡(`NowPlayingSnapshot.trackToken`). 누르는 사이 곡이 바뀌었으면 앱이 요청을 버린다.
    @Parameter(title: "곡", default: "")
    var track: String

    init() {}

    init(fraction: Double, track: String) {
        self.fraction = fraction
        self.track = track
    }

    func perform() async throws -> some IntentResult {
        await SeekRequest.send(fraction: fraction, track: track)
        return .result()
    }
}
