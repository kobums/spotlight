// 소리 없이 "재생 중"이라고 시스템에 알리는 시험용 플레이어. 받은 재생 명령은 찍기만 한다.
//
//   swiftc -O -o /tmp/fake_player Widget/tools/fake_player.swift && /tmp/fake_player [초] [속도]
//
// 음악 앱이 아닌 앱의 재생이 위젯에 나오는지, 위젯 버튼의 명령이 그 앱으로 가는지를
// 듣고 있는 음악을 건드리지 않고 확인한다. 떠 있는 동안 메뉴 막대의 "지금 재생 중"도 이것으로 바뀌고,
// 정한 시간(기본 30초)이 지나면 스스로 끝나 원래대로 돌아간다. 속도(기본 1)를 주면 배속 재생인 척한다.
import AppKit
import MediaPlayer

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 30 : 30
let rate = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 1 : 1
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
setvbuf(stdout, nil, _IOLBF, 0)

let center = MPNowPlayingInfoCenter.default()
var track = 1
var playing = true
var started = Date()
var elapsedAtStart = 30.0

func artwork() -> MPMediaItemArtwork {
    let size = CGSize(width: 600, height: 600)
    return MPMediaItemArtwork(boundsSize: size) { _ in
        let image = NSImage(size: size)
        image.lockFocus()
        (track % 2 == 1 ? NSColor.systemTeal : NSColor.systemOrange).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 150, y: 150, width: 300, height: 300)).fill()
        image.unlockFocus()
        return image
    }
}

func publish() {
    let elapsed = playing ? elapsedAtStart + Date().timeIntervalSince(started) * rate : elapsedAtStart
    center.nowPlayingInfo = [
        MPMediaItemPropertyTitle: "시험용 곡 \(track)",
        MPMediaItemPropertyArtist: "가짜 플레이어",
        MPMediaItemPropertyAlbumTitle: "시험 앨범",
        MPMediaItemPropertyPlaybackDuration: 200.0,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
        MPNowPlayingInfoPropertyPlaybackRate: playing ? rate : 0.0,
        MPMediaItemPropertyArtwork: artwork(),
    ]
    center.playbackState = playing ? .playing : .paused
    print("가짜 플레이어: 곡 \(track) \(playing ? "재생" : "일시 정지") \(Int(elapsed))초")
}

func setPlaying(_ value: Bool) {
    elapsedAtStart = playing ? elapsedAtStart + Date().timeIntervalSince(started) * rate : elapsedAtStart
    started = Date()
    playing = value
    publish()
}

let commands = MPRemoteCommandCenter.shared()
commands.togglePlayPauseCommand.addTarget { _ in print("명령 받음: togglePlayPause"); setPlaying(!playing); return .success }
commands.playCommand.addTarget { _ in print("명령 받음: play"); setPlaying(true); return .success }
commands.pauseCommand.addTarget { _ in print("명령 받음: pause"); setPlaying(false); return .success }
commands.nextTrackCommand.addTarget { _ in print("명령 받음: next"); track += 1; elapsedAtStart = 0; started = Date(); publish(); return .success }
commands.changePlaybackPositionCommand.addTarget { event in
    guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
    print("명령 받음: 위치 \(Int(event.positionTime))초로")
    elapsedAtStart = event.positionTime
    started = Date()
    publish()
    return .success
}
commands.previousTrackCommand.addTarget { _ in print("명령 받음: previous"); track -= 1; elapsedAtStart = 0; started = Date(); publish(); return .success }

publish()
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    center.nowPlayingInfo = nil
    center.playbackState = .stopped
    print("가짜 플레이어: 끝")
    exit(0)
}
app.run()
