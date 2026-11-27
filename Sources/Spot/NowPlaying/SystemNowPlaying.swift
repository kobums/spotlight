import Foundation
import OSLog

/// 시스템의 "지금 재생 중"(메뉴 막대·제어 센터에 나오는 것)을 따라간다. 음악 앱이 아닌 앱의 재생을 보여 주는 데 쓴다.
///
/// 맥에는 이 정보를 읽는 공개 API가 없다. 비공개 프레임워크 MediaRemote는 macOS 15.4부터 애플이 정한 프로그램만 쓸 수 있는데,
/// 시스템의 `/usr/bin/perl`이 그 가운데 하나다. 그래서 perl을 띄워 앱 번들의 도우미 라이브러리(`Helper/NowPlayingHelper.m`)를
/// 불러오게 하고, 그 출력을 읽는다. 공개된 길이 아니라서 macOS가 바뀌면 멈출 수 있다. 멈추면 `state`가 nil로 남고
/// 앱은 음악 앱만 보여 준다.
@MainActor
final class SystemNowPlaying {
    struct State: Equatable, Sendable {
        /// 재생 중인 앱.
        var bundleID: String
        /// 같은 곡인지 가리는 열쇠. 아트가 어느 곡의 것인지 맞출 때 쓴다.
        var key: String
        var isPlaying: Bool
        var title: String
        var artist: String
        var album: String
        /// 곡 길이(초). 모르면 0.
        var duration: TimeInterval
        /// `positionDate` 시점의 재생 위치(초).
        var position: TimeInterval
        var positionDate: Date
        /// 재생 속도. 보통 1이고, 1.5배속이면 1.5.
        var rate: Double
    }

    /// 재생 중인 앱이 없거나 도우미가 돌지 않으면 nil.
    private(set) var state: State?
    /// `revision`은 그림이 올 때마다 올라간다. 같은 곡의 그림이 바뀐 것을 알아보는 데 쓴다.
    private(set) var artwork: (key: String, data: Data, revision: Int)?
    /// `state`나 `artwork`가 바뀌면 부른다.
    var onChange: (() -> Void)?

    private let log = Logger(subsystem: "com.gowoobro.spot.nowplaying", category: "system")
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    /// `buffer` 앞에서부터 줄바꿈이 없다고 이미 확인한 길이. 조각이 올 때마다 처음부터 다시 훑지 않게 한다.
    private var scanned = 0
    /// 한도를 넘은 줄을 버리는 중. 다음 줄바꿈까지는 그 줄의 나머지다.
    private var isSkippingLine = false
    private var artworkRevision = 0
    /// 띄울 때마다 올라간다. 앞서 띄운 도우미가 뒤늦게 보낸 것을 가려낸다.
    private var generation = 0
    private var wantsRunning = false
    private var failures = 0
    private var launchedAt = Date.distantPast
    private var restart: Task<Void, Never>?

    private static let perl = "/usr/bin/perl"
    private static let script = """
        use DynaLoader; \
        my $library = DynaLoader::dl_load_file($ARGV[0], 0) or die "load"; \
        my $entry = DynaLoader::dl_find_symbol($library, "nowplaying_helper_main") or die "symbol"; \
        DynaLoader::dl_install_xsub("main::helper", $entry); \
        main::helper();
        """
    /// 아트 한 장(base64)까지 담을 수 있는 한 줄의 한도.
    private static let maxLineBytes = 16 * 1024 * 1024
    private static let restartDelays: [TimeInterval] = [2, 5, 15, 60, 300]

    func start() {
        guard !wantsRunning else { return }
        wantsRunning = true
        failures = 0
        launch()
    }

    func stop() {
        wantsRunning = false
        restart?.cancel()
        generation += 1
        process?.terminate()
        process = nil
        input = nil
        clear()
    }

    /// 지금 재생 중인 앱에 명령을 보낸다.
    func send(_ command: PlayerCommand) {
        write(command.rawValue)
    }

    /// 지금 재생 중인 앱의 재생 위치를 `position`(초)으로 옮긴다.
    func seek(to position: TimeInterval) {
        write("seek \(position)")
    }

    private func write(_ line: String) {
        guard let input else { return }
        do {
            try input.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            log.error("명령 쓰기 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 도우미 띄우기

    private func launch() {
        guard let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libNowPlayingHelper.dylib"),
              FileManager.default.fileExists(atPath: library.path),
              FileManager.default.isExecutableFile(atPath: Self.perl) else {
            log.error("도우미나 perl이 없어 다른 앱의 재생을 읽지 못함")
            return
        }
        generation += 1
        let generation = generation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perl)
        process.arguments = ["-e", Self.script, library.path]
        // 사용자 환경의 perl 설정(PERL5OPT 등)이 끼어들지 않게 비운다.
        process.environment = [:]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        // 도우미가 죽은 뒤에 명령을 써도 앱이 신호(SIGPIPE)로 죽지 않게 한다.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            // 받은 순서를 지켜 메인으로 넘긴다.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(data, generation: generation) }
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.didExit(status: status, generation: generation) }
            }
        }
        do {
            try process.run()
        } catch {
            log.error("도우미 실행 실패: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.process = process
        self.input = input.fileHandleForWriting
        resetBuffer()
        launchedAt = Date()
    }

    private func didExit(status: Int32, generation: Int) {
        guard generation == self.generation else { return }
        // 끝난 도우미가 남긴 출력이 이 뒤에 도착해도 상태를 되살리지 못하게 한다 (끝남과 출력은 서로 다른 큐로 온다).
        self.generation += 1
        process = nil
        input = nil
        clear()
        guard wantsRunning else { return }
        // 한동안 잘 돌다가 끝난 것이면 처음부터 다시 센다.
        if Date().timeIntervalSince(launchedAt) > 60 { failures = 0 }
        guard failures < Self.restartDelays.count else {
            log.error("도우미가 계속 끝남(마지막 상태 \(status)). 다른 앱의 재생 읽기를 그만둠")
            return
        }
        let delay = Self.restartDelays[failures]
        failures += 1
        log.error("도우미가 끝남(상태 \(status)). \(Int(delay))초 뒤 다시 띄움")
        restart = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, wantsRunning, process == nil else { return }
            launch()
        }
    }

    private func clear() {
        let changed = state != nil || artwork != nil
        state = nil
        artwork = nil
        resetBuffer()
        if changed { onChange?() }
    }

    private func resetBuffer() {
        buffer.removeAll()
        scanned = 0
        isSkippingLine = false
    }

    // MARK: - 도우미가 보낸 것 읽기

    private func receive(_ data: Data, generation: Int) {
        guard generation == self.generation else { return }
        var data = data
        if isSkippingLine {
            guard let newline = data.firstIndex(of: 0x0A) else { return }
            data = Data(data[data.index(after: newline)...])
            isSkippingLine = false
        }
        buffer.append(data)
        // 아트 한 줄은 수 MB가 여러 조각으로 온다. 새로 붙은 곳에서만 줄바꿈을 찾는다.
        while let newline = buffer[(buffer.startIndex + scanned)...].firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer = Data(buffer[buffer.index(after: newline)...])
            scanned = 0
            handle(line: line)
        }
        scanned = buffer.count
        if buffer.count > Self.maxLineBytes {
            resetBuffer()
            isSkippingLine = true
        }
    }

    private func handle(line: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            log.info("도우미 준비됨")
        case "state":
            let next = Self.state(from: message)
            guard next != state else { return }
            state = next
            #if DEBUG
            log.info("시스템: \(next?.bundleID ?? "없음", privacy: .public) \(next.map { $0.isPlaying ? "재생" : "멈춤" } ?? "", privacy: .public) “\(next?.title ?? "", privacy: .public)” \(Int(next?.position ?? 0))/\(Int(next?.duration ?? 0))초")
            #else
            log.info("시스템: \(next?.bundleID ?? "없음", privacy: .public) \(next.map { $0.isPlaying ? "재생" : "멈춤" } ?? "", privacy: .public)")
            #endif
            onChange?()
        case "artwork":
            guard let key = message["key"] as? String, let encoded = message["data"] as? String,
                  let data = Data(base64Encoded: encoded), !data.isEmpty else { return }
            artworkRevision += 1
            artwork = (Self.clipped(key, to: Self.maxKeyLength), data, artworkRevision)
            onChange?()
        case "error":
            log.error("도우미: \(message["message"] as? String ?? "?", privacy: .public)")
        default:
            break
        }
    }

    private static let maxTextLength = 300
    private static let maxKeyLength = 2000
    /// 길이·위치로 받아들이는 가장 큰 값(초).
    private static let maxSeconds: TimeInterval = 48 * 3600

    /// 유니코드 스칼라 `limit`개까지만 남긴다.
    ///
    /// 글자(자소 묶음)로 세면 결합 문자를 끝없이 붙인 "한 글자"가 그대로 통과해, 위젯이 그리다 죽을 수 있다.
    private static func clipped(_ value: String, to limit: Int) -> String {
        let scalars = value.unicodeScalars
        guard scalars.count > limit else { return value }
        return String(String.UnicodeScalarView(scalars.prefix(limit)))
    }

    /// 다른 앱이 시스템에 알린 값을 그대로 믿지 않는다. 숫자는 범위를, 글자는 길이를 본다.
    private static func state(from message: [String: Any]) -> State? {
        guard let bundleID = message["bundle"] as? String, !bundleID.isEmpty, bundleID.utf8.count <= 255,
              let key = message["key"] as? String else { return nil }
        let now = Date()
        func text(_ name: String) -> String { clipped(message[name] as? String ?? "", to: maxTextLength) }
        func seconds(_ name: String) -> TimeInterval {
            let value = (message[name] as? NSNumber)?.doubleValue ?? 0
            return value.isFinite ? value : 0
        }
        var duration = seconds("duration")
        if duration < 0 || duration > maxSeconds { duration = 0 }
        // 길이를 모를 때에도 위치가 터무니없이 커지지 않게 한다.
        var position = min(max(seconds("elapsed"), 0), maxSeconds)
        if duration > 0 { position = min(position, duration) }
        // 되감기(음수)나 터무니없는 속도는 보통 속도로 본다.
        var rate = (message["rate"] as? NSNumber)?.doubleValue ?? 1
        if !rate.isFinite || rate < 0.1 || rate > 8 { rate = 1 }
        // 위치를 잰 시각. 없거나 터무니없으면 지금으로 본다.
        var positionDate = now
        if let timestamp = (message["timestamp"] as? NSNumber)?.doubleValue, timestamp.isFinite {
            let date = Date(timeIntervalSince1970: timestamp)
            if date <= now.addingTimeInterval(5), date > now.addingTimeInterval(-48 * 3600) {
                positionDate = min(date, now)
            }
        }
        return State(bundleID: bundleID, key: clipped(key, to: maxKeyLength), isPlaying: message["playing"] as? Bool ?? false,
                     title: text("title"), artist: text("artist"), album: text("album"),
                     duration: duration, position: position, positionDate: positionDate, rate: rate)
    }
}
