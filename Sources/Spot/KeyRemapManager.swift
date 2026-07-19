import AppKit
import IOKit.hid

/// hidutil UserKeyMapping 기반 키 리맵 — 카라비너 Simple Modifications 대체.
///
/// HID 드라이버 레벨이라 권한이 전혀 필요 없고(입력 모니터링도 아님) 보안 입력 중에도 동작한다.
/// 매핑은 시스템 속성이라 Spot이 종료돼도 유지되지만, 재부팅이나 Bluetooth 키보드
/// 재연결 시 초기화될 수 있어 키보드 연결 이벤트와 잠자기 해제 시 재적용한다.
final class KeyRemapManager {
    static let shared = KeyRemapManager()

    // HID Usage (0x07 = Keyboard/Keypad 페이지)
    private static let rightCommand: UInt64 = 0x7000000E7
    private static let f18: UInt64 = 0x70000006D
    private static let capsLock: UInt64 = 0x700000039
    private static let leftControl: UInt64 = 0x7000000E0

    /// 전 기기 공통 룰. caps→⌃도 전역 적용 — HHKB는 해당 위치가 하드웨어
    /// Control이라 caps_lock 자체를 보내지 않으므로 영향이 없다.
    private let rules: [(src: UInt64, dst: UInt64)] = [
        (rightCommand, f18),      // 우측⌘ → F18 (시스템 "이전 입력 소스" 단축키 = 한/영)
        (capsLock, leftControl),
    ]

    private let enabledKey = "keyRemapEnabled"
    private var hidManager: IOHIDManager?
    private var reapplyWork: DispatchWorkItem?

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// 앱 시작 시 호출 — 활성이면 적용하고, 키보드 연결·잠자기 해제 감시 시작
    func start() {
        if isEnabled { apply() }
        watchKeyboardConnections()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        enabled ? apply() : clear()
    }

    // MARK: - hidutil

    private func apply() {
        let mappings = rules.map {
            "{\"HIDKeyboardModifierMappingSrc\":0x\(String($0.src, radix: 16))," +
            "\"HIDKeyboardModifierMappingDst\":0x\(String($0.dst, radix: 16))}"
        }
        runHidutil("{\"UserKeyMapping\":[\(mappings.joined(separator: ","))]}")
    }

    private func clear() {
        runHidutil("{\"UserKeyMapping\":[]}")
    }

    private func runHidutil(_ payload: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", payload]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - 재적용 트리거

    /// 키보드(Generic Desktop/Keyboard) 장치가 나타날 때마다 매핑 재적용.
    /// 장치 열람만 하고 입력 값은 읽지 않으므로 입력 모니터링 권한이 필요 없다.
    private func watchKeyboardConnections() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: 0x01,
            kIOHIDDeviceUsageKey: 0x06,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<KeyRemapManager>.fromOpaque(context).takeUnretainedValue().scheduleReapply()
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager
    }

    @objc private func workspaceDidWake() {
        scheduleReapply()
    }

    /// 연결 직후엔 장치 이벤트가 연달아 오므로 0.5초 디바운스 후 1회 적용
    private func scheduleReapply() {
        guard isEnabled else { return }
        reapplyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.apply() }
        reapplyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
