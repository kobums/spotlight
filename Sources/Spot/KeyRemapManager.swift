import AppKit
import IOKit.hid

/// hidutil UserKeyMapping 기반 키 리맵 — 카라비너 Simple Modifications·Function Keys 대체.
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
    private static let f1: UInt64 = 0x70000003A
    private static let f2: UInt64 = 0x70000003B
    private static let f10: UInt64 = 0x700000043
    private static let f11: UInt64 = 0x700000044
    private static let f12: UInt64 = 0x700000045

    // HID Usage (0x0C = Consumer 페이지) — 미디어 키
    private static let mute: UInt64 = 0xC000000E2
    private static let volumeUp: UInt64 = 0xC000000E9
    private static let volumeDown: UInt64 = 0xC000000EA
    private static let brightnessUp: UInt64 = 0xC0000006F
    private static let brightnessDown: UInt64 = 0xC00000070

    /// 전 기기 공통 룰. caps→⌃도 전역 적용 — HHKB는 해당 위치가 하드웨어
    /// Control이라 caps_lock 자체를 보내지 않으므로 영향이 없다.
    private let rules: [(src: UInt64, dst: UInt64)] = [
        (rightCommand, f18),      // 우측⌘ → F18 (시스템 "이전 입력 소스" 단축키 = 한/영)
        (capsLock, leftControl),
    ]

    /// 외장(비 Apple) 키보드 전용 룰 — F1·F2·F10~F12를 Apple 키보드처럼 미디어 키로.
    /// HHKB는 F키가 Fn 조합으로만 나오므로 fn+F1/F2 = 밝기, fn+F11/F12 = 볼륨이 된다.
    /// 내장 키보드에는 적용하지 않아 fn+F1/F2로 진짜 F키를 계속 쓸 수 있다.
    ///
    /// 밝기 키는 macOS가 제어할 디스플레이가 없으면 그냥 무시되므로,
    /// 실제 조절은 MediaKeyManager가 이 키를 잡아 외장 모니터로 넘긴다.
    private let externalRules: [(src: UInt64, dst: UInt64)] = [
        (f1, brightnessDown),
        (f2, brightnessUp),
        (f10, mute),
        (f11, volumeDown),
        (f12, volumeUp),
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
        // 전역 룰 먼저, 기기별 룰 나중 — 기기별 --set이 그 기기의 전역 값을 덮어쓰므로
        // 외장 키보드에는 공통 룰을 함께 넣어야 한다
        runHidutil(rules: rules, matching: nil)
        for device in externalKeyboards() {
            runHidutil(rules: rules + externalRules, matching: device)
        }
    }

    private func clear() {
        runHidutil(rules: [], matching: nil)
        for device in externalKeyboards() {
            runHidutil(rules: [], matching: device)
        }
    }

    private func runHidutil(rules: [(src: UInt64, dst: UInt64)],
                            matching: (vendor: Int, product: Int)?) {
        let mappings = rules.map {
            "{\"HIDKeyboardModifierMappingSrc\":0x\(String($0.src, radix: 16))," +
            "\"HIDKeyboardModifierMappingDst\":0x\(String($0.dst, radix: 16))}"
        }
        var arguments = ["property"]
        if let matching {
            arguments += ["--matching",
                          "{\"VendorID\":\(matching.vendor),\"ProductID\":\(matching.product)}"]
        }
        arguments += ["--set", "{\"UserKeyMapping\":[\(mappings.joined(separator: ","))]}"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// 연결된 외장(비 Apple) 키보드의 VendorID/ProductID 목록
    private func externalKeyboards() -> [(vendor: Int, product: Int)] {
        let appleVendorIDs: Set<Int> = [0x05AC, 0x004C]
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: 0x01,
            kIOHIDDeviceUsageKey: 0x06,
        ] as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }

        var seen = Set<Int>()
        var result: [(vendor: Int, product: Int)] = []
        for device in devices {
            let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            guard vendor != 0, !appleVendorIDs.contains(vendor) else { continue }
            guard seen.insert(vendor << 16 | product).inserted else { continue }
            result.append((vendor, product))
        }
        return result
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
