import AppKit
import CoreServices

/// 음악 앱과 Apple Event로 직접 대화한다.
///
/// AppleScript 문자열을 돌리는 `NSAppleScript`는 메인 스레드에서만 쓸 수 있어, 음악 앱이 굼뜨면 이 앱도 같이 멈춘다.
/// 그래서 이벤트를 직접 만들어 전용 큐에서 보내고 응답 제한 시간을 둔다.
/// 네 글자 코드는 `sdef /System/Applications/Music.app`에서 확인한 값.
final class MusicBridge: Sendable {
    static let bundleID = "com.apple.Music"

    enum Permission: Sendable {
        /// 허락됨.
        case granted
        /// 사용자가 거절했다. 시스템 설정에서만 바꿀 수 있다.
        case denied
        /// 아직 물어보지 않았다.
        case undetermined
        /// 음악 앱이 꺼져 있어 알 수 없다.
        case notRunning
    }

    struct Failure: Error, CustomStringConvertible {
        let code: Int
        let message: String

        var description: String { "Apple Event 오류 \(code) \(message)" }
        var isPermissionProblem: Bool { code == Code.notPermitted || code == Code.wouldRequireConsent }
    }

    struct Track: Sendable, Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval

        var key: String { [title, artist, album].joined(separator: "\u{1F}") }
    }

    struct Reading: Sendable {
        var state: NowPlayingSnapshot.PlaybackState
        var track: Track?
        var position: TimeInterval
        /// `position`을 읽은 시각.
        var date: Date
    }

    private enum Code {
        static let noSuchObject = -1728
        static let notPermitted = -1743
        static let wouldRequireConsent = -1744
        static let processNotFound = -600
    }

    private let queue = DispatchQueue(label: "com.gowoobro.spot.nowplaying.music-bridge", qos: .userInitiated)

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    // MARK: - 바깥에서 쓰는 것

    /// 음악 앱 제어 허락 상태. `askIfNeeded`면 아직 묻지 않았을 때 시스템 창을 띄우고 사용자가 답할 때까지 기다린다.
    func permission(askIfNeeded: Bool) async -> Permission {
        guard isRunning else { return .notRunning }
        // 물어보는 호출은 사용자가 답할 때까지 돌아오지 않으므로, 다른 요청이 밀리지 않게 큐를 따로 쓴다.
        let queue = askIfNeeded ? DispatchQueue.global(qos: .userInitiated) : queue
        return await withCheckedContinuation { continuation in
            queue.async {
                let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleID)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askIfNeeded)
                switch Int(status) {
                case 0: continuation.resume(returning: .granted)
                case Code.wouldRequireConsent: continuation.resume(returning: .undetermined)
                case Code.processNotFound: continuation.resume(returning: .notRunning)
                default: continuation.resume(returning: .denied)
                }
            }
        }
    }

    /// 재생 상태, 현재 곡, 재생 위치.
    func read() async throws -> Reading {
        try await run { try self.readSync() }
    }

    /// 현재 곡의 앨범 아트 원본. 없으면 nil. 읽는 사이 곡이 `trackKey`와 달라졌어도 nil.
    func artwork(matching trackKey: String) async throws -> Data? {
        try await run { try self.artworkSync(matching: trackKey) }
    }

    func send(_ command: PlayerCommand) async throws {
        let eventID = switch command {
        case .playPause: "PlPs"
        case .next: "Next"
        // 곡 중간이면 처음으로, 처음이면 이전 곡으로 (⏮ 버튼의 보통 동작)
        case .previous: "Back"
        }
        try await run { _ = try Self.send(eventClass: "hook", eventID: eventID) }
    }

    /// 재생 위치를 `position`(초)으로 옮긴다.
    func seek(to position: TimeInterval) async throws {
        try await run {
            _ = try Self.send(eventClass: "core", eventID: "setd", direct: Self.property("pPos"),
                              data: NSAppleEventDescriptor(double: position))
        }
    }

    // MARK: - 읽기

    private func readSync() throws -> Reading {
        var reading = try readOnce()
        // 곡이 넘어가는 순간에 걸치면 앞뒤 값이 다른 곡의 것일 수 있다. 다 읽고도 같은 곡인지 보고, 아니면 한 번 더.
        if let track = reading.track, try currentTrackTitle() != track.title {
            reading = try readOnce()
        }
        return reading
    }

    private func readOnce() throws -> Reading {
        let state = try playerState()
        guard state != .stopped, let track = try currentTrack() else {
            return Reading(state: .stopped, track: nil, position: 0, date: Date())
        }
        let position = try Self.get(Self.property("pPos"))?.doubleValue ?? 0
        return Reading(state: state, track: track, position: position, date: Date())
    }

    private func playerState() throws -> NowPlayingSnapshot.PlaybackState {
        guard let value = try Self.get(Self.property("pPlS")) else { return .stopped }
        switch value.enumCodeValue {
        case Self.code("kPSP"), Self.code("kPSF"), Self.code("kPSR"): return .playing  // 재생, 빨리 감기, 되감기
        case Self.code("kPSp"): return .paused
        default: return .stopped
        }
    }

    private func currentTrack() throws -> Track? {
        let track = Self.property("pTrk")
        do {
            return Track(
                title: try Self.get(Self.property("pnam", of: track))?.stringValue ?? "",
                artist: try Self.get(Self.property("pArt", of: track))?.stringValue ?? "",
                album: try Self.get(Self.property("pAlb", of: track))?.stringValue ?? "",
                duration: try Self.get(Self.property("pDur", of: track))?.doubleValue ?? 0
            )
        } catch let failure as Failure where failure.code == Code.noSuchObject {
            return nil  // 현재 곡이 없다
        }
    }

    private func currentTrackTitle() throws -> String? {
        do {
            return try Self.get(Self.property("pnam", of: Self.property("pTrk")))?.stringValue ?? ""
        } catch let failure as Failure where failure.code == Code.noSuchObject {
            return nil
        }
    }

    private func artworkSync(matching trackKey: String) throws -> Data? {
        let artwork = Self.element("cArt", at: 1, of: Self.property("pTrk"))
        let data: Data
        do {
            guard let value = try Self.get(Self.property("pRaw", of: artwork), timeout: 5) else { return nil }
            data = value.data
        } catch let failure as Failure where failure.code == Code.noSuchObject {
            return nil  // 아트가 없거나 아직 내려받지 않았다
        }
        guard !data.isEmpty, try currentTrack()?.key == trackKey else { return nil }
        return data
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }

    // MARK: - Apple Event 만들기

    private static func code(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }

    /// `container`의 속성 하나 (예: 현재 곡의 이름).
    private static func property(_ code: String, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        specifier(class: "prop", form: OSType(formPropertyID), data: .init(typeCode: Self.code(code)), container: container)
    }

    /// `container`의 `index`번째 요소 (예: 현재 곡의 첫 번째 아트).
    private static func element(_ code: String, at index: Int32, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(class: code, form: OSType(formAbsolutePosition), data: .init(int32: index), container: container)
    }

    private static func specifier(class desiredClass: String, form: OSType, data: NSAppleEventDescriptor,
                                  container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: code(desiredClass)), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(.init(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) ?? record
    }

    /// 값을 읽는다. 값이 비어 있으면(missing value) nil.
    private static func get(_ specifier: NSAppleEventDescriptor, timeout: TimeInterval = 3) throws -> NSAppleEventDescriptor? {
        guard let value = try send(eventClass: "core", eventID: "getd", direct: specifier, timeout: timeout) else { return nil }
        if value.descriptorType == DescType(typeType), value.typeCodeValue == code("msng") { return nil }
        return value
    }

    @discardableResult
    private static func send(eventClass: String, eventID: String, direct: NSAppleEventDescriptor? = nil,
                             data: NSAppleEventDescriptor? = nil,
                             timeout: TimeInterval = 3) throws -> NSAppleEventDescriptor? {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: code(eventClass),
            eventID: code(eventID),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let direct {
            event.setParam(direct, forKeyword: AEKeyword(keyDirectObject))
        }
        if let data {
            event.setParam(data, forKeyword: AEKeyword(keyAEData))  // "set … to 값"의 값
        }
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
        } catch {
            let error = error as NSError
            throw Failure(code: error.code, message: error.localizedDescription)
        }
        if let number = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), number.int32Value != 0 {
            let message = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue ?? ""
            throw Failure(code: Int(number.int32Value), message: message)
        }
        return reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
    }
}
