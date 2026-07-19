import Carbon.HIToolbox

/// 글로벌 핫키 관리. Carbon RegisterEventHotKey는 입력 모니터링 권한이 필요 없다.
final class HotKeyManager {
    enum HotKeyID: UInt32 {
        case launcher = 1 // ⌥Space
        case hints = 2    // ⌃Space

        // 창 배치 — 사용자가 Rectangle에서 쓰던 단축키 그대로
        case windowLeftHalf = 10, windowRightHalf, windowTopHalf, windowBottomHalf
        case windowTopLeft, windowTopRight, windowBottomLeft, windowBottomRight
        case windowMaximize, windowMaximizeHeight, windowCenter, windowRestore
        case windowSmaller, windowLarger, windowNextDisplay, windowPrevDisplay
    }

    static let shared = HotKeyManager()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    func register(_ id: HotKeyID, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        installEventHandlerIfNeeded()
        handlers[id.rawValue] = handler

        let hotKeyID = EventHotKeyID(signature: OSType(0x53504F54), id: id.rawValue) // 'SPOT'
        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        refs[id.rawValue] = ref
    }

    fileprivate func dispatch(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let id = hotKeyID.id
            DispatchQueue.main.async {
                HotKeyManager.shared.dispatch(id: id)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
