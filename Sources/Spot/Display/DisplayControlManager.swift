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
        var contrast: Int?    // DDC 모니터 중 대비 VCP를 지원하는 것만, 0~100 캐시
        var muted: Bool
        /// 결합 디밍 — DDC 밝기 0 밑으로 계속 내릴 때의 감마 스케일 (100 = 없음).
        /// MonitorControl의 "hardware+software dimming" 방식. DDC 모니터 전용.
        var swDim: Int = 100

        var isDDC: Bool { if case .ddc = method { return true }; return false }
        var methodLabel: String { isDDC ? "DDC" : "감마" }
    }

    /// 미디어 키 HUD 등에 돌려줄 조작 결과
    struct Feedback {
        enum Kind { case brightness, volume, contrast }
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
    /// 조작 피드백 표시기 — 미디어 키·런처 명령 공용 (패널이 하나라 첫 대상 모니터에 띄운다)
    private let hud = DisplayHUD()
    private var rescanWork: DispatchWorkItem?

    private init() {
        AudioOutputMonitor.shared.start()
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
                guard let brightness else { return DDCProbe(display: display, brightness: nil, volume: nil, contrast: nil, muted: false) }
                return DDCProbe(
                    display: display,
                    brightness: Self.percent(brightness),
                    volume: DDCService.read(display.avService, vcp: DDCService.VCP.volume).map(Self.percent),
                    contrast: DDCService.read(display.avService, vcp: DDCService.VCP.contrast).map(Self.percent),
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
        let contrast: Int?
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
                contrast: probe.contrast,
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
                contrast: nil,
                muted: false))
        }

        // DDC로 승격된 화면에 감마 디밍이 남아 있으면 백라이트와 겹쳐 이중으로
        // 어두워진다. 걷어내고 나머지만 되살린다.
        var promoted = false
        for displayID in claimed where gamma.forget(displayID) { promoted = true }
        if promoted { CGDisplayRestoreColorSyncSettings() }

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
        var feedback: Feedback?
        for index in matching(target) {
            // 절대값 지정은 결합 디밍을 걷어내고 그 값으로 — "밝기 50"은 항상 백라이트 50
            if !relative { setSwDim(at: index, to: 100) }
            let applied = applyBrightness(at: index, to: relative ? monitors[index].brightness + value : value)
            if feedback == nil {
                feedback = Feedback(kind: .brightness, name: monitors[index].name,
                                    value: applied, muted: false, displayID: monitors[index].displayID)
            }
        }
        if let feedback { hud.show(feedback) }
    }

    /// 대비 설정 (DDC 대비 VCP를 지원하는 모니터만)
    func setContrast(_ value: Int, target: String?, relative: Bool) {
        var feedback: Feedback?
        for index in matching(target) {
            guard let current = monitors[index].contrast else { continue }
            let applied = applyContrast(at: index, to: relative ? current + value : value)
            if feedback == nil {
                feedback = Feedback(kind: .contrast, name: monitors[index].name,
                                    value: applied, muted: false, displayID: monitors[index].displayID)
            }
        }
        if let feedback { hud.show(feedback) }
    }

    /// 볼륨 설정 (DDC 볼륨을 지원하는 모니터만)
    func setVolume(_ value: Int, target: String?, relative: Bool) {
        var feedback: Feedback?
        for index in matching(target) {
            guard let current = monitors[index].volume else { continue }
            let applied = applyVolume(at: index, to: relative ? current + value : value)
            if feedback == nil {
                feedback = Feedback(kind: .volume, name: monitors[index].name,
                                    value: applied, muted: false, displayID: monitors[index].displayID)
            }
        }
        if let feedback { hud.show(feedback) }
    }

    /// 음소거 토글 (DDC 모니터만)
    func toggleMute(target: String?) {
        var feedback: Feedback?
        for index in matching(target) where monitors[index].isDDC {
            let muted = !monitors[index].muted
            applyMute(at: index, to: muted)
            if feedback == nil {
                feedback = Feedback(kind: .volume, name: monitors[index].name,
                                    value: monitors[index].volume ?? 0, muted: muted,
                                    displayID: monitors[index].displayID)
            }
        }
        if let feedback { hud.show(feedback) }
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
        if let feedback { hud.show(feedback) }
        return feedback
    }

    /// 볼륨 미디어 키. 대상은 커서 위치가 아니라 **기본 오디오 출력 장치와 이름이
    /// 일치하는 모니터** (MonitorControl의 오디오 장치 매칭 방식) — 소리는 커서와
    /// 무관하게 한 곳으로 나가므로 밝기와 같은 화면별 라우팅을 쓰면 안 된다.
    /// 매칭 모니터가 없으면 nil — 호출자가 이벤트를 시스템에 넘긴다 (내장 스피커 등).
    @discardableResult
    func adjustVolume(by delta: Int) -> Feedback? {
        let indices = audioTargets().filter { monitors[$0].volume != nil }
        guard !indices.isEmpty else { return nil }
        var feedback: Feedback?
        for index in indices {
            let value = applyVolume(at: index, to: (monitors[index].volume ?? 0) + delta)
            if feedback == nil {
                feedback = Feedback(kind: .volume, name: monitors[index].name,
                                    value: value, muted: false, displayID: monitors[index].displayID)
            }
        }
        if let feedback { hud.show(feedback) }
        return feedback
    }

    /// 음소거 미디어 키. 볼륨과 같은 오디오 장치 매칭. 매칭 없으면 nil.
    @discardableResult
    func toggleMute() -> Feedback? {
        let indices = audioTargets()
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
        if let feedback { hud.show(feedback) }
        return feedback
    }

    /// 볼륨·음소거 키의 대상 모니터.
    ///
    /// 1순위: 기본 오디오 출력 장치와 이름이 일치하는 DDC 모니터 (공백·숫자 무시 비교).
    /// 2순위: 이름 매칭이 안 됐지만 시스템도 그 장치의 볼륨을 못 다루면(DP/HDMI 오디오)
    ///        볼륨 지원 DDC 모니터 전체 — 모니터가 오디오 쪽 이름을 화면과 다르게
    ///        신고하는 기종에서 키가 통째로 죽는 것을 막는다.
    /// 빈 배열: 시스템이 제어 가능한 장치(내장 스피커·에어팟 등) — 이벤트를 양보한다.
    private func audioTargets() -> [Int] {
        let audio = AudioOutputMonitor.shared
        if let deviceName = audio.deviceName {
            let device = AudioOutputMonitor.normalized(deviceName)
            let matched = monitors.indices.filter {
                monitors[$0].isDDC && AudioOutputMonitor.normalized(monitors[$0].name) == device
            }
            if !matched.isEmpty { return matched }
        }
        if !audio.systemCanControlVolume {
            return monitors.indices.filter { monitors[$0].volume != nil }
        }
        return []
    }

    /// 볼륨 키가 지금 어디로 가는지 — 런처 진단 표시용
    func volumeKeyTargetNames() -> [String] {
        audioTargets().map { monitors[$0].name }
    }

    /// 해당 디스플레이의 모니터 인덱스. 못 찾으면 전체를 대상으로 한다.
    private func targeting(_ displayID: CGDirectDisplayID?) -> [Int] {
        guard let displayID else { return Array(monitors.indices) }
        let matched = monitors.indices.filter { monitors[$0].displayID == displayID }
        return matched.isEmpty ? Array(monitors.indices) : matched
    }

    // MARK: - 적용 (메인에서 캐시 갱신 → 큐에서 하드웨어 쓰기)

    /// 새 밝기를 캐시에 반영하고 하드웨어 쓰기를 예약. 실제 적용된 값을 돌려준다.
    ///
    /// DDC 모니터는 결합 디밍(MonitorControl 방식)을 지원한다: 요청 값이 0 밑이면
    /// 백라이트 최저에서 멈추지 않고 감마로 이어서 어두워지고, 올릴 때는 감마부터
    /// 원복한 뒤 백라이트를 올린다. 감마가 남아 있는 동안 밝기 캐시는 0이다.
    @discardableResult
    private func applyBrightness(at index: Int, to value: Int) -> Int {
        switch monitors[index].method {
        case .ddc(let service):
            var value = value
            // 올리기: 남아 있는 감마 디밍을 먼저 걷어낸다
            if value > 0, monitors[index].swDim < 100 {
                let restored = min(100, monitors[index].swDim + value)
                value -= restored - monitors[index].swDim
                setSwDim(at: index, to: restored)
            }
            let clamped = max(0, min(100, value))
            // 내리기: DDC 0 밑으로 남는 몫은 감마로
            if value < 0 {
                setSwDim(at: index, to: monitors[index].swDim + value)
            }
            if clamped != monitors[index].brightness || value >= 0 {
                monitors[index].brightness = clamped
                queue.async { DDCService.write(service, vcp: DDCService.VCP.brightness, value: clamped) }
            }
            return clamped
        case .gamma(let displayID):
            // 감마는 화면이 완전히 검어지면 조작 불능이 되므로 하한을 둔다
            let clamped = max(GammaDimmer.minPercent, min(100, value))
            monitors[index].brightness = clamped
            gamma.setBrightness(clamped, of: displayID)
            return clamped
        }
    }

    /// DDC 모니터의 결합 디밍 감마 적용 (displayID를 모르면 조용히 무시)
    private func setSwDim(at index: Int, to value: Int) {
        guard let displayID = monitors[index].displayID else { return }
        let clamped = max(GammaDimmer.minPercent, min(100, value))
        guard clamped != monitors[index].swDim else { return }
        monitors[index].swDim = clamped
        if clamped == 100 {
            gamma.reset(displayID)
        } else {
            gamma.setBrightness(clamped, of: displayID)
        }
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

    @discardableResult
    private func applyContrast(at index: Int, to value: Int) -> Int {
        guard case .ddc(let service) = monitors[index].method else { return monitors[index].contrast ?? 0 }
        let clamped = max(0, min(100, value))
        monitors[index].contrast = clamped
        queue.async { DDCService.write(service, vcp: DDCService.VCP.contrast, value: clamped) }
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
