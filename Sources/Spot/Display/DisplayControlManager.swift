import AppKit
import CoreGraphics

/// 모니터 밝기·볼륨 제어 통합 계층 (MonitorControl 대체).
///
/// 모니터별 제어 방법을 자동 판정한다: DDC 응답하면 하드웨어 제어, 아니면 감마 디밍.
/// DDC 통신은 수십 ms라 전용 직렬 큐에서 하고, 검색 UI는 캐시된 상태만 읽는다.
final class DisplayControlManager {
    static let shared = DisplayControlManager()

    enum Method {
        case ddc(CFTypeRef)              // 하드웨어 (밝기·볼륨)
        case gamma(CGDirectDisplayID)    // 소프트웨어 디밍 (밝기만)
    }

    struct Monitor {
        let name: String
        let method: Method
        var brightness: Int   // 0~100 캐시
        var volume: Int?      // DDC 모니터만, 0~100 캐시
        var muted: Bool

        var isDDC: Bool { if case .ddc = method { return true }; return false }
        var methodLabel: String { isDDC ? "DDC" : "감마" }
    }

    /// 메인 스레드에서 읽는 캐시 (rescan/쓰기 완료 시 갱신)
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

    /// 외장 모니터 열거 + DDC 프로브 + 초기 상태 읽기
    func rescan() {
        queue.async { [weak self] in
            guard let self else { return }
            var found: [Monitor] = []
            var ddcUUIDs = Set<String>()

            for display in DDCService.externalDisplays() {
                // DDC 프로브: 밝기가 읽히는 서비스만 하드웨어 제어로 채택
                guard let brightness = DDCService.read(display.avService, vcp: DDCService.VCP.brightness) else { continue }
                let volume = DDCService.read(display.avService, vcp: DDCService.VCP.volume)
                let mute = DDCService.read(display.avService, vcp: DDCService.VCP.mute)
                if let uuid = display.edidUUID { ddcUUIDs.insert(uuid) }
                found.append(Monitor(
                    name: display.productName ?? "외장 모니터",
                    method: .ddc(display.avService),
                    brightness: percent(brightness),
                    volume: volume.map(percent),
                    muted: mute.map { $0.current == DDCService.muteOn } ?? false))
            }

            // DDC로 못 잡은 외장 CGDisplay → 감마 디밍
            for cgID in Self.onlineExternalDisplays() {
                let uuid = Self.edidUUID(of: cgID)
                if let uuid, ddcUUIDs.contains(uuid) { continue }
                // DDC 모니터 수가 UUID 매칭 실패로 어긋나는 경우: 이름이 겹치면 스킵
                let name = Self.displayName(of: cgID) ?? "외장 모니터"
                if found.contains(where: { $0.name == name && $0.isDDC }) { continue }
                found.append(Monitor(name: name, method: .gamma(cgID),
                                     brightness: self.gamma.brightness(of: cgID),
                                     volume: nil, muted: false))
            }

            DispatchQueue.main.async {
                self.monitors = found
                self.gamma.reapplyAll()
            }
        }
    }

    // MARK: - 제어

    /// 밝기 설정. target이 nil이면 전체. relative면 value를 증감량으로 해석.
    func setBrightness(_ value: Int, target: String?, relative: Bool) {
        forEachTarget(target) { index, monitor in
            let newValue = self.clampPercent(relative ? monitor.brightness + value : value,
                                        floor: monitor.isDDC ? 0 : GammaDimmer.minPercent)
            switch monitor.method {
            case .ddc(let service):
                DDCService.write(service, vcp: DDCService.VCP.brightness, value: newValue)
            case .gamma(let cgID):
                DispatchQueue.main.sync { self.gamma.setBrightness(newValue, of: cgID) }
            }
            return { $0.brightness = newValue }
        }
    }

    /// 볼륨 설정 (DDC 모니터만)
    func setVolume(_ value: Int, target: String?, relative: Bool) {
        forEachTarget(target) { index, monitor in
            guard case .ddc(let service) = monitor.method, let current = monitor.volume else { return nil }
            let newValue = self.clampPercent(relative ? current + value : value, floor: 0)
            DDCService.write(service, vcp: DDCService.VCP.volume, value: newValue)
            return { $0.volume = newValue; $0.muted = false }
        }
    }

    /// 음소거 토글 (DDC 모니터만)
    func toggleMute(target: String?) {
        forEachTarget(target) { index, monitor in
            guard case .ddc(let service) = monitor.method else { return nil }
            let newMuted = !monitor.muted
            DDCService.write(service, vcp: DDCService.VCP.mute,
                             value: newMuted ? DDCService.muteOn : DDCService.muteOff)
            return { $0.muted = newMuted }
        }
    }

    /// 이름 토큰으로 모니터 선택 ("lg" → "LG HDR 4K"). nil이면 전체.
    func matching(_ target: String?) -> [Int] {
        guard let target, !target.isEmpty else { return Array(monitors.indices) }
        let lowered = target.lowercased()
        return monitors.indices.filter { monitors[$0].name.lowercased().contains(lowered) }
    }

    // MARK: - 내부

    /// 대상 모니터마다 큐에서 작업 실행 후, 돌려준 클로저로 캐시를 갱신한다
    private func forEachTarget(_ target: String?, _ operation: @escaping (Int, Monitor) -> ((inout Monitor) -> Void)?) {
        let indices = matching(target)
        queue.async { [weak self] in
            guard let self else { return }
            for index in indices {
                guard index < self.monitors.count else { continue }
                let monitor = self.monitors[index]
                guard let update = operation(index, monitor) else { continue }
                DispatchQueue.main.async {
                    guard index < self.monitors.count else { return }
                    update(&self.monitors[index])
                }
            }
        }
    }

    private func percent(_ value: (current: Int, max: Int)) -> Int {
        guard value.max > 0 else { return value.current }
        return Int((Double(value.current) / Double(value.max) * 100).rounded())
    }

    private func clampPercent(_ value: Int, floor: Int) -> Int {
        max(floor, min(100, value))
    }

    private static func onlineExternalDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return Array(ids.prefix(Int(count))).filter { CGDisplayIsBuiltin($0) == 0 }
    }

    private static func edidUUID(of display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String?
    }

    private static func displayName(of display: CGDirectDisplayID) -> String? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display
        }?.localizedName
    }
}
