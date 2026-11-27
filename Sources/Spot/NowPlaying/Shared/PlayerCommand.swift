import Foundation
import OSLog
import notify

private let commandLog = Logger(subsystem: "com.gowoobro.spot.nowplaying", category: "command")

/// 위젯 버튼이 앱에 부탁하는 재생 명령.
///
/// 위젯 확장은 음악 앱을 직접 제어할 권한이 없다. 그래서 Darwin 알림으로 앱을 부르고,
/// 실제 제어는 "음악 앱 제어" 허락을 받은 앱이 한다.
enum PlayerCommand: String, CaseIterable, Sendable {
    case playPause, next, previous

    var notificationName: String { "com.gowoobro.spot.nowplaying.command.\(rawValue)" }

    func post() {
        notify_post(notificationName)
    }

    /// 명령을 보내고, 앱이 바뀐 상태를 써 줄 때까지 잠깐 기다린다.
    /// 버튼 처리가 끝나면 시스템이 위젯을 다시 그리는데, 그때 새 상태가 바로 보이게 하려는 것.
    func send(timeout: Duration = .milliseconds(1200)) async {
        commandLog.info("버튼 \(rawValue, privacy: .public) 보냄")
        let before = SharedStore.load()?.updatedAt
        post()
        await Self.waitForUpdate(since: before, timeout: timeout)
    }

    /// 앱이 상태 파일을 고쳐 쓸 때까지 기다린다.
    static func waitForUpdate(since before: Date?, timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            if SharedStore.load()?.updatedAt != before { return }
        }
    }

    /// 앱 쪽: 명령이 오면 메인 큐에서 `handler`를 부른다.
    static func observe(_ handler: @escaping @Sendable (PlayerCommand) -> Void) {
        for command in allCases {
            var token: Int32 = 0
            let status = notify_register_dispatch(command.notificationName, &token, .main) { _ in
                handler(command)
            }
            if status != NOTIFY_STATUS_OK {
                commandLog.error("명령 \(command.rawValue, privacy: .public) 알림 등록 실패(\(status))")
            }
        }
    }
}

/// 위젯의 진행 막대를 눌러 재생 위치를 옮겨 달라는 요청.
///
/// Darwin 알림에는 값을 실을 수 없어, 어디로 옮길지는 App Group 폴더의 파일에 적고 알림으로 앱을 깨운다.
enum SeekRequest {
    private static let notificationName = "com.gowoobro.spot.nowplaying.command.seek"
    private static let fileName = "seek-request.json"
    /// 이보다 오래된 요청은 버린다. 앱이 꺼져 있던 동안의 요청이 나중에 실행되지 않게 한다.
    private static let lifetime: TimeInterval = 5
    /// 요청 파일로 받아들이는 가장 큰 크기. 정상 파일은 100바이트 안팎이다.
    private static let maxFileBytes = 4096

    private struct Payload: Codable {
        var fraction: Double
        var date: Date
        /// 위젯이 그리고 있던 곡(`NowPlayingSnapshot.trackToken`).
        var track: String?
    }

    /// - Parameters:
    ///   - fraction: 곡 길이에 대한 비율(0…1).
    ///   - track: 위젯이 그리고 있던 곡의 `trackToken`. 앱은 지금 곡과 다르면 요청을 버린다.
    static func send(fraction: Double, track: String, timeout: Duration = .milliseconds(1200)) async {
        guard fraction.isFinite else {
            commandLog.error("막대: 위치 값이 잘못되어 보내지 않음")
            return
        }
        let fraction = min(max(fraction, 0), 1)
        commandLog.info("막대 \(Int(fraction * 100))% 보냄")
        let before = SharedStore.load()?.updatedAt
        do {
            let data = try JSONEncoder().encode(Payload(fraction: fraction, date: Date(), track: track))
            try SharedStore.writeFile(data, name: fileName)
        } catch {
            commandLog.error("막대: 요청 파일 쓰기 실패: \(error.localizedDescription, privacy: .public)")
            return
        }
        notify_post(notificationName)
        await PlayerCommand.waitForUpdate(since: before, timeout: timeout)
    }

    /// 앱 쪽: 요청이 오면 메인 큐에서 `handler`를 비율, 위젯이 그리고 있던 곡의 표와 함께 부른다.
    static func observe(_ handler: @escaping @Sendable (_ fraction: Double, _ track: String) -> Void) {
        var token: Int32 = 0
        let status = notify_register_dispatch(notificationName, &token, .main) { _ in
            guard let payload = takeRequest() else { return }
            handler(payload.fraction, payload.track ?? "")
        }
        if status != NOTIFY_STATUS_OK {
            commandLog.error("위치 요청 알림 등록 실패(\(status))")
        }
    }

    /// 요청 파일을 읽고 지운다. 쓸 수 없는 요청이면 까닭을 남기고 nil.
    private static func takeRequest() -> Payload? {
        guard let url = SharedStore.fileURL(fileName) else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        // 같은 App Group에 쓸 수 있는 프로세스가 둔 것일 수 있다. 보통 파일이고 작을 때만 읽는다.
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
            commandLog.info("위치 요청: 알림은 왔는데 요청 파일이 없음")
            return nil
        }
        guard values.isRegularFile == true, let size = values.fileSize, size <= maxFileBytes,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            commandLog.error("위치 요청: 요청 파일을 읽을 수 없어 버림")
            return nil
        }
        guard payload.fraction.isFinite, (0...1).contains(payload.fraction) else {
            commandLog.error("위치 요청: 위치 값이 범위 밖이라 버림")
            return nil
        }
        guard abs(payload.date.timeIntervalSinceNow) <= lifetime else {
            commandLog.info("위치 요청: 오래된 요청이라 버림")
            return nil
        }
        return payload
    }
}
