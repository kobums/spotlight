import AppKit
import CoreGraphics

/// 모니터 밝기·볼륨 제어 통합 계층 (MonitorControl 대체).
///
/// 모니터별 제어 방법을 자동 판정한다: DDC에 응답하면 하드웨어 제어, 아니면 감마 디밍.
/// DDC 통신은 수십 ms라 전용 직렬 큐에서 하고, 캐시(monitors)는 메인 스레드 전용이다.
///
/// 값 계산·캐시 갱신을 메인에서 즉시 끝내고 하드웨어 쓰기만 큐로 넘기는 구조라,
/// 밝기 키를 꾹 눌러 반복 입력이 쏟아져도 단계가 누락되지 않는다.
final class DisplayControlManager {
    static let shared = DisplayControlManager()

    enum Method {
        case ddc(CFTypeRef)              // 하드웨어 (밝기·볼륨)
        case gamma(CGDirectDisplayID)    // 소프트웨어 디밍 (밝기만)
    }

    struct Monitor {
        let name: String
        let method: Method
        /// 화면 좌표 매칭용. DDC 모니터도 EDID로 역추적해 채운다.
        let displayID: CGDirectDisplayID?
        var brightness: Int   // 0~100 캐시
        var volume: Int?      // DDC 모니터 중 볼륨 VCP를 지원하는 것만, 0~100 캐시
        var muted: Bool

        var isDDC: Bool { if case .ddc = method { return true }; return false }
        var methodLabel: String { isDDC ? "DDC" : "감마" }
    }

    /// 미디어 키 HUD 등에 돌려줄 조작 결과
    struct Feedback {
        enum Kind { case brightness, volume }
        let kind: Kind
        let name: String
        let value: Int
        let muted: Bool
        let displayID: CGDirectDisplayID?
    }

    /// 메인 스레드 전용 캐시
    private(set) var monitors: [Monitor] = []

    private let queue = DispatchQueue(label: "spot.display", qos: .userInitiated)
    private let gamma = GammaDimmer()
    private var rescanWork: DispatchWorkItem?

    private init() {
        rescan()
        // 모니터 연결/해제·해상도 변경 감지 → 재스캔 (연속 이벤트 디바운스)
        CGDisplayRegisterReconfigurationCallback({ _, _, userInfo in
            guard let userInfo else { return }
            Unmanaged<DisplayControlManager>.fromOpaque(userInfo).takeUnretainedValue().scheduleRescan()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func scheduleRescan() {
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescan() }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - 스캔

    /// 외장 모니터 열거 + DDC 프로브 + 초기 상태 읽기.
    /// 느린 I²C 프로브는 큐에서, 조립·캐시 갱신은 메인에서 한다.
    func rescan() {
        queue.async { [weak self] in
            guard let self else { return }
            let probes: [DDCProbe] = DDCService.externalDisplays().map { display in
                // 밝기가 읽히는 서비스만 하드웨어 제어로 채택
                let brightness = DDCService.read(display.avService, vcp: DDCService.VCP.brightness)
                guard let brightness else { return DDCProbe(display: display, brightness: nil, volume: nil, muted: false) }
                return DDCProbe(
                    display: display,
                    brightness: Self.percent(brightness),
                    volume: DDCService.read(display.avService, vcp: DDCService.VCP.volume).map(Self.percent),
                    muted: DDCService.read(display.avService, vcp: DDCService.VCP.mute)
                        .map { $0.current == DDCService.muteOn } ?? false)
            }
            DispatchQueue.main.async { self.assemble(probes) }
        }
    }

    private struct DDCProbe {
        let display: DDCService.ExternalDisplay
        let brightness: Int?   // nil = DDC 미지원
        let volume: Int?
        let muted: Bool
    }

    /// DDC 프로브 결과 + 감마 폴백을 합쳐 캐시를 재구성 (메인 전용)
    private func assemble(_ probes: [DDCProbe]) {
        let external = Self.onlineExternalDisplays()
        var claimed = Set<CGDirectDisplayID>()
        var result: [Monitor] = []

        for probe in probes {
            guard let brightness = probe.brightness else { continue }
            let displayID = probe.display.identity.flatMap { identity in
                external.first { Self.matches($0, identity) }
            }
            if let displayID { claimed.insert(displayID) }
            result.append(Monitor(
                name: displayID.flatMap(Self.displayName) ?? probe.display.identity?.productName ?? "외장 모니터",
                method: .ddc(probe.display.avService),
                displayID: displayID,
                brightness: brightness,
                volume: probe.volume,
                muted: probe.muted))
        }

        // DDC로 못 잡은 외장 디스플레이 → 감마 디밍
        for displayID in external where !claimed.contains(displayID) {
            result.append(Monitor(
                name: Self.displayName(displayID) ?? "외장 모니터",
                method: .gamma(displayID),
                displayID: displayID,
                brightness: gamma.brightness(of: displayID),
                volume: nil,
                muted: false))
        }

        monitors = result
        gamma.reapplyAll()
    }

    /// EDID 신원 ↔ CGDirectDisplayID 대조. 세 값 모두 EDID에서 오므로 정확히 일치한다.
    private static func matches(_ displayID: CGDirectDisplayID, _ identity: DDCService.Identity) -> Bool {
        CGDisplayVendorNumber(displayID) == identity.vendor
            && CGDisplayModelNumber(displayID) == identity.model
            && CGDisplaySerialNumber(displayID) == identity.serial
    }

    // MARK: - 검색 명령용 제어 (이름 토큰 대상)

    /// 밝기 설정. target이 nil이면 전체. relative면 value를 증감량으로 해석.
    func setBrightness(_ value: Int, target: String?, relative: Bool) {
        for index in matching(target) {
            applyBrightness(at: index, to: relative ? monitors[index].brightness + value : value)
        }
    }

    /// 볼륨 설정 (DDC 볼륨을 지원하는 모니터만)
    func setVolume(_ value: Int, target: String?, relative: Bool) {
        for index in matching(target) {
            guard let current = monitors[index].volume else { continue }
            applyVolume(at: index, to: relative ? current + value : value)
        }
    }

    /// 음소거 토글 (DDC 모니터만)
    func toggleMute(target: String?) {
        for index in matching(target) where monitors[index].isDDC {
            applyMute(at: index, to: !monitors[index].muted)
        }
    }

    /// 이름 토큰으로 모니터 선택 ("lg" → "LG HDR 4K"). nil이면 전체.
    func matching(_ target: String?) -> [Int] {
        guard let target, !target.isEmpty else { return Array(monitors.indices) }
        let lowered = target.lowercased()
        return monitors.indices.filter { monitors[$0].name.lowercased().contains(lowered) }
    }

    // MARK: - 미디어 키용 제어 (디스플레이 대상)

    /// 밝기 상대 조절. displayID가 nil이거나 못 찾으면 전체 모니터.
    /// 제어 대상이 하나도 없으면 nil — 호출자가 이벤트를 시스템에 넘기면 된다.
    @discardableResult
    func adjustBrightness(by delta: Int, displayID: CGDirectDisplayID?) -> Feedback? {
        let indices = targeting(displayID)
        guard !indices.isEmpty else { return nil }
        var feedback: Feedback?
        for index in indices {
            let value = applyBrightness(at: index, to: monitors[index].brightness + delta)
            if feedback == nil {
                feedback = Feedback(kind: .brightness, name: monitors[index].name,
                                    value: value, muted: false, displayID: monitors[index].displayID)
            }
        }
        return feedback
    }

    /// 볼륨 상대 조절. DDC 볼륨을 지원하는 모니터가 없으면 nil.
    @discardableResult
    func adjustVolume(by delta: Int, displayID: CGDirectDisplayID?) -> Feedback? {
        let indices = targeting(displayID).filter { monitors[$0].volume != nil }
        guard !indices.isEmpty else { return nil }
        var feedback: Feedback?
        for index in indices {
            let value = applyVolume(at: index, to: (monitors[index].volume ?? 0) + delta)
            if feedback == nil {
                feedback = Feedback(kind: .volume, name: monitors[index].name,
                                    value: value, muted: false, displayID: monitors[index].displayID)
            }
        }
        return feedback
    }

    /// 음소거 토글. DDC 모니터가 없으면 nil.
    @discardableResult
    func toggleMute(displayID: CGDirectDisplayID?) -> Feedback? {
        let indices = targeting(displayID).filter { monitors[$0].isDDC }
        guard !indices.isEmpty else { return nil }
        var feedback: Feedback?
        for index in indices {
            let muted = !monitors[index].muted
            applyMute(at: index, to: muted)
            if feedback == nil {
                feedback = Feedback(kind: .volume, name: monitors[index].name,
                                    value: monitors[index].volume ?? 0, muted: muted,
                                    displayID: monitors[index].displayID)
            }
        }
        return feedback
    }

    /// 해당 디스플레이의 모니터 인덱스. 못 찾으면 전체를 대상으로 한다.
    private func targeting(_ displayID: CGDirectDisplayID?) -> [Int] {
        guard let displayID else { return Array(monitors.indices) }
        let matched = monitors.indices.filter { monitors[$0].displayID == displayID }
        return matched.isEmpty ? Array(monitors.indices) : matched
    }

    // MARK: - 적용 (메인에서 캐시 갱신 → 큐에서 하드웨어 쓰기)

    /// 새 밝기를 캐시에 반영하고 하드웨어 쓰기를 예약. 실제 적용된 값을 돌려준다.
    @discardableResult
    private func applyBrightness(at index: Int, to value: Int) -> Int {
        // 감마는 화면이 완전히 검어지면 조작 불능이 되므로 하한을 둔다
        let floor = monitors[index].isDDC ? 0 : GammaDimmer.minPercent
        let clamped = max(floor, min(100, value))
        monitors[index].brightness = clamped
        switch monitors[index].method {
        case .ddc(let service):
            queue.async { DDCService.write(service, vcp: DDCService.VCP.brightness, value: clamped) }
        case .gamma(let displayID):
            gamma.setBrightness(clamped, of: displayID)
        }
        return clamped
    }

    @discardableResult
    private func applyVolume(at index: Int, to value: Int) -> Int {
        guard case .ddc(let service) = monitors[index].method else { return monitors[index].volume ?? 0 }
        let clamped = max(0, min(100, value))
        monitors[index].volume = clamped
        monitors[index].muted = false
        queue.async { DDCService.write(service, vcp: DDCService.VCP.volume, value: clamped) }
        return clamped
    }

    private func applyMute(at index: Int, to muted: Bool) {
        guard case .ddc(let service) = monitors[index].method else { return }
        monitors[index].muted = muted
        queue.async {
            DDCService.write(service, vcp: DDCService.VCP.mute,
                             value: muted ? DDCService.muteOn : DDCService.muteOff)
        }
    }

    // MARK: - 내부

    private static func percent(_ value: (current: Int, max: Int)) -> Int {
        guard value.max > 0 else { return value.current }
        return Int((Double(value.current) / Double(value.max) * 100).rounded())
    }

    private static func onlineExternalDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return Array(ids.prefix(Int(count))).filter { CGDisplayIsBuiltin($0) == 0 }
    }

    private static func displayName(_ display: CGDirectDisplayID) -> String? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display
        }?.localizedName
    }
}
