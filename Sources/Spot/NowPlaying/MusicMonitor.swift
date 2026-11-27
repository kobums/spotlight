import AppKit
import OSLog
import WidgetKit

/// 음악 앱의 재생 상태를 따라가며 위젯용 상태 파일을 쓰고 위젯을 새로 고친다.
///
/// 변화를 아는 길은 둘이다.
/// - 재생 알림(`com.apple.Music.playerInfo`): 곡이 바뀌거나 재생·일시 정지할 때 음악 앱이 보낸다. 허락이 필요 없다.
/// - Apple Event: 재생 위치와 앨범 아트는 직접 물어봐야 한다. "음악 앱 제어" 허락이 필요하다.
///   곡 안에서 위치를 옮기는 것은 알림이 오지 않아, 재생 중에는 몇 초마다 위치를 확인한다.
///
/// Spot에서는 `NowPlayingService`가 위젯이 놓여 있을 때만 켠다 (`start`/`stop`).
@MainActor
final class MusicMonitor {
    private(set) var snapshot: NowPlayingSnapshot?
    private(set) var permission: MusicBridge.Permission = .notRunning
    /// 음악 앱이 아닌 앱(Spotify, 브라우저 등)의 재생도 위젯에 보여 줄지. 메뉴에서 끌 수 있다.
    private(set) var showsOtherApps = MusicMonitor.storedShowsOtherApps
    /// `start`와 `stop` 사이인지. 꺼져 있는 동안에는 알림·명령이 와도 아무것도 하지 않는다.
    private(set) var isRunning = false
    private var didRegisterObservers = false

    private let bridge = MusicBridge()
    private let log = Logger(subsystem: "com.gowoobro.spot.nowplaying", category: "monitor")

    /// 지난 실행이 남긴 상태. 같은 곡이면 앨범 아트 파일을 다시 만들지 않고 이어 쓴다.
    private var previousRun: NowPlayingSnapshot?
    private var isUpdating = false
    private var needsUpdate = false
    private var pendingInfo: PlayerInfo?
    private var isAskingPermission = false
    private var artworkRetry: Task<Void, Never>?
    private let system = SystemNowPlaying()
    /// 지금 위젯에 음악 앱이 아닌 앱의 재생을 보여 주고 있는지. `snapshot`과 어긋나지 않게 `commit`에서만 바꾼다.
    private var isShowingOtherApp = false
    /// 다른 앱의 앨범 아트를 줄여 둔 파일. 그림이 올 때(`revision`)마다 한 번만 만든다. 그림을 읽지 못했으면 `files`가 nil.
    private var otherAppArtwork: (key: String, revision: Int, files: (artwork: String, backdrop: String)?)?
    private var pollTimer: Timer?
    private static let showsOtherAppsKey = "nowPlayingShowsOtherApps"
    /// 모니터를 만들기 전에도(위젯을 아직 놓지 않았을 때) 메뉴가 읽고 쓸 수 있게 저장값을 따로 연다.
    static var storedShowsOtherApps: Bool {
        get { UserDefaults.standard.object(forKey: showsOtherAppsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showsOtherAppsKey) }
    }
    private var pollInterval: TimeInterval?

    // MARK: - 시작

    func start() {
        guard !isRunning else { return }
        isRunning = true
        previousRun = SharedStore.load()
        registerObserversOnce()
        if showsOtherApps { system.start() }
        checkPermissionAndUpdate()
    }

    /// 위젯에 빈 상태를 남기고 멈춘다. 도우미도 끈다.
    func stop() {
        guard isRunning else { return }
        artworkRetry?.cancel()
        system.stop()
        pollTimer?.invalidate()
        pollTimer = nil
        pollInterval = nil
        commit(NowPlayingSnapshot(), reason: "꺼짐")
        isRunning = false
        log.info("멈춤")
    }

    private func registerObserversOnce() {
        guard !didRegisterObservers else { return }
        didRegisterObservers = true

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] notification in
            let info = PlayerInfo(userInfo: notification.userInfo)
            MainActor.assumeIsolated { self?.requestUpdate(info: info) }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard Self.isMusic(notification) else { return }
            MainActor.assumeIsolated { self?.checkPermissionAndUpdate() }
        }
        workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard Self.isMusic(notification) else { return }
            MainActor.assumeIsolated { self?.requestUpdate() }
        }
        // 잠자기에서 깨어나면 타이머가 쉬는 동안 달라진 것을 바로 맞춘다.
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestUpdate() }
        }

        PlayerCommand.observe { [weak self] command in
            MainActor.assumeIsolated { self?.handle(command) }
        }
        SeekRequest.observe { [weak self] fraction, track in
            MainActor.assumeIsolated { self?.seek(toFraction: fraction, track: track) }
        }

        system.onChange = { [weak self] in self?.requestUpdate() }

        #if DEBUG
        // Widget/tools/debug_state.sh가 위젯에 보여 줄 가짜 상태를 바꾼 뒤 부른다.
        DebugState.observeReload {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nowPlaying)
        }
        #endif
    }

    private nonisolated static func isMusic(_ notification: Notification) -> Bool {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier == MusicBridge.bundleID
    }

    // MARK: - 메뉴에서 부르는 것

    func openMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicBridge.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// 위젯을 눌렀을 때: 지금 보여 주고 있는 재생의 앱을 연다.
    func openSource() {
        if isShowingOtherApp, let bundleID = system.state?.bundleID {
            // 번들이 없는 프로그램(명령줄 도구 등)이면 열 것이 없다.
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            openMusic()
        }
    }

    func setShowsOtherApps(_ enabled: Bool) {
        guard enabled != showsOtherApps else { return }
        showsOtherApps = enabled
        Self.storedShowsOtherApps = enabled
        log.info("다른 앱의 재생 표시: \(enabled)")
        guard isRunning else { return }
        if enabled { system.start() } else { system.stop() }
        requestUpdate()
    }

    /// 허락을 받는다. 이미 거절한 뒤라면 시스템이 다시 묻지 않으므로 설정 화면을 연다.
    func requestPermission() {
        if permission == .denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // 음악 앱이 꺼져 있으면 물어볼 수 없다. 켜 두면 켜진 것을 보고 묻는다.
            if bridge.isRunning { checkPermissionAndUpdate() } else { openMusic() }
        }
    }

    // MARK: - 허락

    /// 허락 상태를 확인한 다음 상태를 읽는다. 아직 물어본 적이 없으면 시스템 창을 띄워 묻는다.
    ///
    /// 이미 허락된 경우에는 묻는 절차를 거치지 않고 바로 읽는다. 그러지 않으면 켤 때마다
    /// "읽을 수 없음"이 먼저 반영되어 위젯이 잠깐 빈 화면이 된다.
    private func checkPermissionAndUpdate() {
        guard isRunning else { return }
        Task {
            if permission != .granted {
                setPermission(await bridge.permission(askIfNeeded: false))
            }
            if permission == .undetermined, !isAskingPermission {
                isAskingPermission = true
                Task {
                    let value = await bridge.permission(askIfNeeded: true)
                    isAskingPermission = false
                    setPermission(value)
                    requestUpdate()
                }
            }
            requestUpdate()
        }
    }

    private func setPermission(_ value: MusicBridge.Permission) {
        guard value != permission else { return }
        permission = value
        log.info("음악 앱 제어 허락: \(String(describing: value), privacy: .public)")
    }

    // MARK: - 상태 따라가기

    /// 상태를 다시 읽어 달라고 한다. 읽는 중에 또 부르면 끝난 뒤 한 번만 더 읽는다.
    private func requestUpdate(info: PlayerInfo? = nil) {
        guard isRunning else { return }
        if let info { pendingInfo = info }
        needsUpdate = true
        guard !isUpdating else { return }
        isUpdating = true
        Task {
            while needsUpdate, isRunning {
                needsUpdate = false
                let info = pendingInfo
                pendingInfo = nil
                await update(info: info)
            }
            isUpdating = false
            reschedulePolling()
        }
    }

    /// - Parameter info: 재생 알림에 실려 온 정보. Apple Event를 못 쓸 때(허락 전)는 이것만으로 그린다.
    private func update(info: PlayerInfo?) async {
        // 시스템이 "지금 재생 중"으로 꼽은 앱이 음악 앱이 아니면 그쪽을 보여 준다.
        // 다만 그 앱은 멈춰 있고 음악 앱이 재생 중이면 음악 앱이 먼저다 (아래에서 음악 앱을 읽은 뒤에 가린다).
        let musicIsRunning = await confirmMusicIsRunning()
        if !musicIsRunning { setPermission(.notRunning) }
        let other = otherAppState
        if let other, other.isPlaying || !musicIsRunning {
            await show(other)
            return
        }

        guard musicIsRunning else {
            commit(NowPlayingSnapshot(), reason: "음악 앱 꺼짐")
            return
        }

        // 허락을 묻는 창이 떠 있는 동안에는 Apple Event를 보내도 답이 올 때까지 멈춰 있으므로 보내지 않는다.
        var reading: MusicBridge.Reading?
        if !isAskingPermission {
            if permission != .granted {
                setPermission(await bridge.permission(askIfNeeded: false))
            }
            if permission == .granted {
                do {
                    reading = try await bridge.read()
                } catch let failure as MusicBridge.Failure {
                    log.error("상태 읽기 실패: \(failure.description, privacy: .public)")
                    if failure.isPermissionProblem { setPermission(.denied) }
                } catch {}
            }
        }

        if let other {
            let musicIsPlaying = reading.map { $0.state == .playing } ?? (info?.state == .playing)
            if !musicIsPlaying {
                await show(other)
                return
            }
        }

        var next: NowPlayingSnapshot
        if let reading {
            next = NowPlayingSnapshot()
            next.state = reading.state
            if let track = reading.track {
                next.title = track.title
                next.artist = track.artist
                next.album = track.album
                next.duration = track.duration
                next.position = reading.position
                next.positionDate = reading.date
            }
        } else if let info {
            next = info.snapshot(following: snapshot)
        } else if snapshot == nil || isShowingOtherApp {
            // 막 켜졌는데 읽을 길이 없다. 지난 실행이 남긴 상태가 위젯에 남지 않도록 비운다.
            // 다른 앱을 보여 주다가 그 앱이 사라졌는데(또는 스위치를 껐는데) 음악 앱도 읽을 수 없을 때도 마찬가지다.
            // 그대로 두면 사라진 앱의 곡이 위젯에 남고 버튼은 음악 앱으로 간다.
            next = NowPlayingSnapshot()
        } else {
            return
        }

        if next.hasTrack {
            let known = [snapshot, previousRun].compactMap { $0 }.first { $0.trackKey == next.trackKey && $0.artworkFile != nil }
            if let known {
                next.artworkFile = known.artworkFile
                next.backdropFile = known.backdropFile
            } else if reading != nil, let files = await loadArtwork(for: next.trackKey) {
                next.artworkFile = files.artwork
                next.backdropFile = files.backdrop
            }
        }

        commit(next, reason: reading != nil ? "읽음" : info != nil ? "알림" : "읽지 못함")

        // 스트리밍 곡은 아트가 조금 늦게 준비되기도 한다.
        if next.hasTrack, next.artworkFile == nil, permission == .granted {
            retryArtwork(for: next.trackKey)
        }
    }

    /// 음악 앱이 실행 중인지. 켜져 있는 줄 알았는데 꺼져 있다고 나오면 잠깐 뒤 한 번 더 본다.
    ///
    /// 다른 앱이 끝나는 순간에, 실행 중인 음악 앱이 한 번 "꺼짐"으로 읽혀 위젯이 잠깐 비었던 적이 있다.
    private func confirmMusicIsRunning() async -> Bool {
        if bridge.isRunning { return true }
        guard permission != .notRunning else { return false }
        try? await Task.sleep(for: .milliseconds(300))
        return bridge.isRunning
    }

    // MARK: - 다른 앱의 재생

    /// 시스템의 "지금 재생 중"이 음악 앱이 아닌 앱을 가리킬 때 그 상태.
    private var otherAppState: SystemNowPlaying.State? {
        guard showsOtherApps, let state = system.state, state.bundleID != MusicBridge.bundleID,
              !(state.title.isEmpty && state.artist.isEmpty) else { return nil }
        return state
    }

    private func show(_ state: SystemNowPlaying.State) async {
        var next = NowPlayingSnapshot()
        next.state = state.isPlaying ? .playing : .paused
        next.title = state.title
        next.artist = state.artist
        next.album = state.album
        next.duration = state.duration
        next.position = state.position
        next.positionDate = state.positionDate
        next.rate = state.rate

        // 같은 곡이어도 그림이 새로 왔으면(늦게 준비됐거나 바뀌었으면) 다시 만든다.
        if let artwork = system.artwork, artwork.key == state.key,
           otherAppArtwork?.key != state.key || otherAppArtwork?.revision != artwork.revision {
            let data = artwork.data
            let processed = await Task.detached(priority: .userInitiated) { ArtworkProcessor.process(data) }.value
            var files: (artwork: String, backdrop: String)?
            if let processed {
                let stamp = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
                let names = (artwork: "artwork-\(stamp).jpg", backdrop: "backdrop-\(stamp).jpg")
                do {
                    try SharedStore.writeFile(processed.artwork, name: names.artwork)
                    try SharedStore.writeFile(processed.backdrop, name: names.backdrop)
                    files = names
                } catch {
                    log.error("앨범 아트 쓰기 실패: \(error.localizedDescription, privacy: .public)")
                }
            }
            // 새 그림을 읽지 못했으면 같은 곡의 앞 그림을 그대로 쓴다.
            let earlier = otherAppArtwork?.key == state.key ? otherAppArtwork?.files : nil
            otherAppArtwork = (state.key, artwork.revision, files ?? earlier)
        }
        if let known = otherAppArtwork, known.key == state.key, let files = known.files {
            next.artworkFile = files.artwork
            next.backdropFile = files.backdrop
        }

        commit(next, reason: "시스템", fromOtherApp: true)
    }

    /// - Parameter fromOtherApp: 음악 앱이 아닌 앱의 재생인지. 위젯 버튼의 명령을 어디로 보낼지가 이것으로 정해진다.
    private func commit(_ candidate: NowPlayingSnapshot, reason: String, fromOtherApp: Bool = false) {
        // 읽는 도중에 꺼졌으면 늦게 온 결과로 위젯을 다시 채우지 않는다.
        guard isRunning else { return }
        isShowingOtherApp = fromOtherApp
        if let snapshot, !Self.isWorthRedrawing(from: snapshot, to: candidate) { return }
        var next = candidate
        next.updatedAt = Date()
        let previous = snapshot
        snapshot = next
        do {
            try SharedStore.save(next)
        } catch {
            log.error("상태 파일 쓰기 실패: \(error.localizedDescription, privacy: .public)")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nowPlaying)
        #if DEBUG
        log.info("\(reason, privacy: .public) → \(next.state.rawValue, privacy: .public) “\(next.title, privacy: .public)” \(Int(next.position))/\(Int(next.duration))초 아트 \(next.artworkFile ?? "없음", privacy: .public)")
        #else
        log.info("\(reason, privacy: .public) → \(next.state.rawValue, privacy: .public) 아트 \(next.artworkFile != nil)")
        #endif

        // 위젯이 아직 앞의 상태를 그리고 있을 수 있어 바로 앞 파일까지는 남긴다.
        // 다른 앱의 곡으로 되돌아오면 줄여 둔 그림을 다시 쓰므로, 음악 앱을 보여 주는 동안에도 지우지 않는다.
        var keep = Set([next, previous, previousRun].compactMap { $0 }.flatMap { [$0.artworkFile, $0.backdropFile] }.compactMap { $0 })
        if let files = otherAppArtwork?.files {
            keep.formUnion([files.artwork, files.backdrop])
        }
        SharedStore.removeFiles(withPrefix: "artwork-", keeping: keep)
        SharedStore.removeFiles(withPrefix: "backdrop-", keeping: keep)
    }

    /// 위젯을 다시 그릴 만큼 달라졌는지. 재생 중 위치는 위젯이 스스로 흘리므로, 탐색해서 어긋났을 때만 고친다.
    private static func isWorthRedrawing(from old: NowPlayingSnapshot, to new: NowPlayingSnapshot) -> Bool {
        if old.state != new.state || old.trackKey != new.trackKey || old.artworkFile != new.artworkFile { return true }
        guard new.hasTrack else { return false }
        if abs(old.duration - new.duration) > 0.5 || abs(old.rate - new.rate) > 0.01 { return true }
        return abs(old.position(at: new.positionDate) - new.position) > 1.5
    }

    // MARK: - 앨범 아트

    private func loadArtwork(for trackKey: String) async -> (artwork: String, backdrop: String)? {
        do {
            guard let data = try await bridge.artwork(matching: trackKey) else { return nil }
            let processed = await Task.detached(priority: .userInitiated) { ArtworkProcessor.process(data) }.value
            guard let processed else {
                log.error("앨범 아트를 읽지 못함 (\(data.count) 바이트)")
                return nil
            }
            let stamp = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
            let files = (artwork: "artwork-\(stamp).jpg", backdrop: "backdrop-\(stamp).jpg")
            try SharedStore.writeFile(processed.artwork, name: files.artwork)
            try SharedStore.writeFile(processed.backdrop, name: files.backdrop)
            return files
        } catch {
            log.error("앨범 아트 가져오기 실패: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func retryArtwork(for trackKey: String) {
        artworkRetry?.cancel()
        artworkRetry = Task {
            for delay in [0.8, 2.0, 5.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, !isShowingOtherApp, let current = snapshot,
                      current.trackKey == trackKey, current.artworkFile == nil else { return }
                guard let files = await loadArtwork(for: trackKey) else { continue }
                guard !Task.isCancelled, !isShowingOtherApp, var updated = snapshot, updated.trackKey == trackKey else { return }
                updated.artworkFile = files.artwork
                updated.backdropFile = files.backdrop
                commit(updated, reason: "아트 도착")
                return
            }
        }
    }

    // MARK: - 재생 위치 확인

    private func reschedulePolling() {
        var interval: TimeInterval?
        // 다른 앱의 재생은 도우미가 바뀔 때마다 알려 주므로 주기 확인이 필요 없다.
        if permission == .granted, !isShowingOtherApp, let snapshot, snapshot.hasTrack {
            interval = snapshot.isPlaying ? 4 : 20
        }
        guard interval != pollInterval else { return }
        pollInterval = interval
        pollTimer?.invalidate()
        pollTimer = nil
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestUpdate() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - 위젯 버튼

    /// 위젯의 진행 막대를 눌렀을 때: 곡 길이의 `fraction` 지점으로 옮긴다.
    /// - Parameter track: 위젯이 그리고 있던 곡의 `trackToken`.
    private func seek(toFraction fraction: Double, track: String) {
        guard isRunning else { return }
        guard let snapshot, snapshot.hasTrack, snapshot.duration > 0 else {
            log.info("위치 옮기기 버림: 옮길 곡이 없음")
            return
        }
        // 누르는 사이 곡이 넘어갔거나 보여 주는 앱이 바뀌었으면, 앞 곡 기준의 위치가 새 곡에 적용되므로 버린다.
        guard track == snapshot.trackToken else {
            log.info("위치 옮기기 버림: 위젯이 그리던 곡과 지금 곡이 다름")
            return
        }
        // 맨 끝을 누르면 곡이 바로 넘어가 버리므로 끝에서 조금 앞까지만 간다.
        let position = min(fraction * snapshot.duration, max(snapshot.duration - 2, 0))
        log.info("위치 옮기기 \(Int(fraction * 100))%")
        if isShowingOtherApp {
            system.seek(to: position)
            return
        }
        Task {
            guard bridge.isRunning else { return }
            do {
                try await bridge.seek(to: position)
            } catch {
                log.error("위치 옮기기 실패: \(String(describing: error), privacy: .public)")
            }
            // 위치를 옮긴 것은 재생 알림이 오지 않아 직접 다시 읽는다.
            try? await Task.sleep(for: .milliseconds(150))
            requestUpdate()
        }
    }

    private func handle(_ command: PlayerCommand) {
        guard isRunning else { return }
        log.info("명령 \(command.rawValue, privacy: .public) 받음")
        if isShowingOtherApp {
            // 상태가 바뀌면 도우미가 알려 준다.
            system.send(command)
            return
        }
        Task {
            guard bridge.isRunning else {
                openMusic()
                return
            }
            do {
                try await bridge.send(command)
            } catch {
                log.error("명령 \(command.rawValue, privacy: .public) 실패: \(String(describing: error), privacy: .public)")
            }
            // 곡 처음으로 되감기처럼 재생 알림이 오지 않는 변화도 있어 직접 한 번 더 읽는다.
            try? await Task.sleep(for: .milliseconds(150))
            requestUpdate()
        }
    }
}

/// 재생 알림(`com.apple.Music.playerInfo`)에 실려 오는 정보.
struct PlayerInfo: Sendable {
    var state: NowPlayingSnapshot.PlaybackState
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval

    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo, let state = userInfo["Player State"] as? String else { return nil }
        switch state {
        case "Playing": self.state = .playing
        case "Paused": self.state = .paused
        default: self.state = .stopped
        }
        title = userInfo["Name"] as? String ?? ""
        artist = userInfo["Artist"] as? String ?? ""
        album = userInfo["Album"] as? String ?? ""
        duration = ((userInfo["Total Time"] as? NSNumber)?.doubleValue ?? 0) / 1000
    }

    /// 알림만으로 다음 상태를 만든다. 재생 위치는 알림에 없어 앞의 상태에서 이어 짐작한다.
    func snapshot(following previous: NowPlayingSnapshot?, now: Date = Date()) -> NowPlayingSnapshot {
        var next = NowPlayingSnapshot()
        next.state = state
        guard state != .stopped else { return next }
        next.title = title
        next.artist = artist
        next.album = album
        next.duration = duration
        next.positionDate = now
        if let previous, previous.hasTrack, previous.trackKey == next.trackKey {
            next.position = previous.position(at: now)  // 같은 곡: 재생·일시 정지만 바뀌었다
        } else {
            next.position = 0  // 새 곡은 처음부터
        }
        return next
    }
}
