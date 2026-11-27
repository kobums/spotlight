import Foundation

/// 앱이 음악 앱에서 읽어 위젯에 넘기는 "지금 재생 중" 상태.
struct NowPlayingSnapshot: Codable, Equatable, Sendable {
    enum PlaybackState: String, Codable, Sendable {
        case playing, paused, stopped
    }

    var state: PlaybackState = .stopped
    var title = ""
    var artist = ""
    var album = ""
    /// 곡 길이(초). 스트림처럼 길이를 모르면 0.
    var duration: TimeInterval = 0
    /// `positionDate` 시점의 재생 위치(초).
    var position: TimeInterval = 0
    var positionDate = Date.distantPast
    /// 재생 속도. 음악 앱은 늘 1이고, 다른 앱의 배속 재생(1.5배 등)일 때만 다르다.
    var rate: Double = 1
    /// App Group 폴더 안의 앨범 아트 파일 이름.
    var artworkFile: String?
    /// 앨범 아트를 흐리고 어둡게 만든 배경 파일 이름.
    var backdropFile: String?
    var updatedAt = Date.distantPast

    init() {}

    // 앱과 위젯의 버전이 잠깐 어긋나도 읽히도록 항목마다 기본값을 둔다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(PlaybackState.self, forKey: .state) ?? .stopped
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        position = try c.decodeIfPresent(TimeInterval.self, forKey: .position) ?? 0
        positionDate = try c.decodeIfPresent(Date.self, forKey: .positionDate) ?? .distantPast
        let rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? 1
        self.rate = rate.isFinite && rate > 0 ? rate : 1
        artworkFile = try c.decodeIfPresent(String.self, forKey: .artworkFile)
        backdropFile = try c.decodeIfPresent(String.self, forKey: .backdropFile)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

extension NowPlayingSnapshot {
    /// 보여 줄 곡이 있는지. 멈춤(정지) 상태에는 음악 앱에 "현재 곡"이 없다.
    var hasTrack: Bool {
        state != .stopped && !(title.isEmpty && artist.isEmpty)
    }

    var isPlaying: Bool { state == .playing }

    /// 같은 곡인지 가리는 열쇠. 스트리밍 곡은 재생 알림에 고유 ID가 실려 오지 않아 글자 정보로 만든다.
    var trackKey: String {
        [title, artist, album].joined(separator: "\u{1F}")
    }

    /// 곡을 가리키는 짧은 표. 위젯 버튼의 요청에 실어, 어느 곡을 보고 누른 것인지 앱에 알린다.
    /// 앱과 위젯은 다른 프로세스라 실행마다 달라지는 `hashValue`는 쓸 수 없어 직접 계산한다(FNV-1a).
    var trackToken: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in trackKey.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// 보통 속도로 재생하는지. 배속이면 시스템의 시간 글자(실제 시간으로만 흐른다)를 쓸 수 없다.
    var isNormalSpeed: Bool { abs(rate - 1) < 0.01 }

    /// `date` 시점의 재생 위치(초).
    func position(at date: Date) -> TimeInterval {
        var value = position
        if state == .playing {
            value += date.timeIntervalSince(positionDate) * rate
        }
        value = max(value, 0)
        return duration > 0 ? min(value, duration) : value
    }

    /// 재생 중일 때 곡이 시작한 시각과 끝날 시각. 위젯의 진행 막대와 시간이 스스로 흐르도록 넘긴다.
    /// 배속 재생이면 실제 시간으로는 그만큼 짧다.
    var playbackInterval: ClosedRange<Date>? {
        guard state == .playing, duration > 0, rate > 0 else { return nil }
        let start = positionDate.addingTimeInterval(-position / rate)
        return start...start.addingTimeInterval(duration / rate)
    }

    /// 곡이 끝난 뒤에도 앱이 새 상태를 쓰지 않았을 때(앱이 꺼진 경우) 보여 줄, 끝에서 멈춘 모습.
    var endedCopy: NowPlayingSnapshot {
        var copy = self
        copy.state = .paused
        copy.position = duration
        return copy
    }
}

extension NowPlayingSnapshot {
    /// 위젯 갤러리 미리 보기용.
    static let sample: NowPlayingSnapshot = {
        var s = NowPlayingSnapshot()
        s.state = .paused
        s.title = "곡 제목"
        s.artist = "아티스트"
        s.album = "앨범"
        s.duration = 214
        s.position = 72
        return s
    }()
}

/// 초를 "3:07" 꼴로.
func formatPlaybackTime(_ seconds: TimeInterval) -> String {
    // 다른 앱이 알린 값도 들어오므로, 정수로 바꾸다 죽지 않게 범위를 먼저 본다.
    guard seconds.isFinite else { return "0:00" }
    let total = Int(min(max(seconds.rounded(.down), 0), 359_999))
    let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
