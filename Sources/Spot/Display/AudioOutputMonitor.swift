import CoreAudio
import Foundation

/// 기본 오디오 출력 장치 감시 — 볼륨 미디어 키의 대상 모니터를 고르는 근거.
///
/// MonitorControl의 "오디오 장치 이름 매칭" 방식: 볼륨 키는 커서 위치가 아니라
/// **지금 소리가 나가는 장치**와 이름이 일치하는 모니터로 가야 한다.
/// (커서 기준으로 하면 스피커 없는 모니터에 커서가 있을 때 볼륨 키가 죽는다.)
///
/// 장치 이름은 키 입력마다 조회하지 않고 변경 리스너로 캐시한다 (메인 스레드 전용).
final class AudioOutputMonitor {
    static let shared = AudioOutputMonitor()

    /// 현재 기본 출력 장치 이름 (예: "LG HDR 4K", "MacBook Pro 스피커")
    private(set) var deviceName: String?
    /// macOS가 기본 출력 장치의 볼륨을 직접 조절할 수 있는가.
    /// 내장 스피커·에어팟은 true, DisplayPort/HDMI 오디오는 false —
    /// false면 볼륨 키를 시스템에 넘겨도 아무 일도 일어나지 않는다는 뜻이다.
    private(set) var systemCanControlVolume = false

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        refresh()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let deviceID = Self.defaultOutputDeviceID()
        deviceName = deviceID.flatMap(Self.name(of:))
        systemCanControlVolume = deviceID.map(Self.canSetVolume(of:)) ?? false
    }

    /// 모니터 이름 ↔ 오디오 장치 이름 대조용 정규화 — MonitorControl과 동일하게
    /// 공백·숫자를 걷어낸다 ("LG HDR 4K" → "lghdrk"). 같은 제품이 화면 쪽과
    /// 오디오 쪽에서 미묘하게 다른 이름을 쓰는 경우를 흡수한다.
    static func normalized(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && !$0.isNumber }
    }

    private static func defaultOutputDeviceID() -> AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func name(of deviceID: AudioObjectID) -> String? {
        var name: CFString?
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, $0)
        }
        guard status == noErr else { return nil }
        return name as String?
    }

    /// 장치의 출력 볼륨이 설정 가능한지 — 가상 메인 볼륨 또는 채널별 볼륨이
    /// settable이면 macOS 볼륨 키가 이 장치에서 동작한다 (MonitorControl의
    /// canSetVirtualMainVolume 판정과 같은 목적).
    private static func canSetVolume(of deviceID: AudioObjectID) -> Bool {
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            var settable = DarwinBoolean(false)
            if AudioObjectHasProperty(deviceID, &address),
               AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
               settable.boolValue {
                return true
            }
        }
        return false
    }
}
