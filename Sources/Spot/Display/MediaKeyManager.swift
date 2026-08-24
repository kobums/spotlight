import AppKit
import CoreGraphics

/// 키보드의 밝기·볼륨 미디어 키를 가로채 외장 모니터 제어로 돌린다 (MonitorControl 대체).
///
/// macOS는 내장 디스플레이가 없거나 외장 모니터가 애플 지원 모델이 아니면 밝기 키를
/// 무시하고, DisplayPort/HDMI로 나가는 오디오는 볼륨 키를 아예 받지 않는다.
/// 이 이벤트 탭이 그 키를 잡아 DisplayControlManager(DDC 또는 감마)로 넘긴다.
///
/// 우리가 처리한 키만 삼키고, 제어 대상이 없으면 이벤트를 그대로 흘려보내
/// 내장 디스플레이·일반 오디오 장치의 기본 동작을 해치지 않는다.
final class MediaKeyManager {
    static let shared = MediaKeyManager()

    // NX 시스템 정의 이벤트의 미디어 키 종류 (IOKit ev_keymap.h)
    private enum MediaKey: Int32 {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    /// 미디어 키가 실려 오는 이벤트 종류. CGEventType에는 이 값(14)에 해당하는
    /// 케이스가 없어 CGEventType(rawValue:)로는 만들 수 없다 — raw 값으로만 비교한다.
    private static let systemDefinedRawType = NSEvent.EventType.systemDefined.rawValue
    /// systemDefined 이벤트 중 미디어 키를 나르는 서브타입 (NX_SUBTYPE_AUX_CONTROL_BUTTONS)
    private static let auxControlSubtype: Int16 = 8

    /// 기본 조절 폭. macOS 밝기 눈금이 16단계라 100/16 ≈ 6.
    private static let coarseStep = 6
    /// ⇧⌥ 동시 입력 시 미세 조절 (macOS의 1/4 눈금 관례)
    private static let fineStep = 2

    private let enabledKey = "mediaKeysEnabled"
    private let hud = DisplayHUD()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// 탭이 실제로 살아 있는지 (권한 없으면 false)
    var isRunning: Bool { tap != nil }

    // MARK: - 수명 주기

    func start() {
        guard isEnabled, tap == nil else { return }
        // 이벤트 탭은 손쉬운 사용 권한이 필요하다. 없으면 조용히 포기하고,
        // 메뉴에서 다시 켤 때 프롬프트를 띄운다.
        guard AXIsProcessTrusted() else { return }

        let mask = CGEventMask(1 << Self.systemDefinedRawType)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<MediaKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        tap = nil
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            AccessibilityPermission.ensureTrusted()
            start()
        } else {
            stop()
        }
    }

    // MARK: - 이벤트 처리

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 타임아웃이나 사용자 입력으로 탭이 꺼지면 되살린다
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == Self.systemDefinedRawType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlSubtype
        else { return Unmanaged.passUnretained(event) }

        let data = nsEvent.data1
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let flags = data & 0x0000_FFFF
        let isKeyDown = ((flags & 0xFF00) >> 8) == 0x0A
        guard isKeyDown, let key = MediaKey(rawValue: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        // 런루프 소스를 메인에 달았으므로 이 콜백은 메인 스레드에서 불린다 —
        // 캐시(메인 전용)를 그대로 읽고, 삼킬지 여부를 동기로 결정한다.
        // 하드웨어 쓰기는 DisplayControlManager가 큐로 넘기므로 탭이 막히지 않는다.
        let handled = Thread.isMainThread
            ? perform(key, modifiers: nsEvent.modifierFlags)
            : DispatchQueue.main.sync { self.perform(key, modifiers: nsEvent.modifierFlags) }
        return handled ? nil : Unmanaged.passUnretained(event)
    }

    /// 실제 제어 수행. 제어 대상이 없으면 false를 돌려 이벤트를 시스템에 넘긴다.
    private func perform(_ key: MediaKey, modifiers: NSEvent.ModifierFlags) -> Bool {
        let manager = DisplayControlManager.shared
        let fine = modifiers.contains(.shift) && modifiers.contains(.option)
        let step = fine ? Self.fineStep : Self.coarseStep
        let displayID = Self.displayUnderCursor()

        let feedback: DisplayControlManager.Feedback?
        switch key {
        case .brightnessUp:   feedback = manager.adjustBrightness(by: step, displayID: displayID)
        case .brightnessDown: feedback = manager.adjustBrightness(by: -step, displayID: displayID)
        case .soundUp:        feedback = manager.adjustVolume(by: step, displayID: displayID)
        case .soundDown:      feedback = manager.adjustVolume(by: -step, displayID: displayID)
        case .mute:           feedback = manager.toggleMute(displayID: displayID)
        }

        guard let feedback else { return false }
        hud.show(feedback)
        return true
    }

    /// 마우스 포인터가 올라가 있는 디스플레이 — 조절 대상을 그 화면으로 좁힌다
    private static func displayUnderCursor() -> CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        return screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
