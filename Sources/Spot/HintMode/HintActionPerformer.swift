import ApplicationServices

/// 선택된 요소 실행과 마우스 이벤트 합성. AXPress를 우선 시도하고, 실패하거나
/// 캐럿 위치가 중요한 텍스트 입력류는 실제 클릭 이벤트를 합성한다.
enum HintActionPerformer {
    private static let clickFirstRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField"]

    static func perform(_ target: HintTarget) {
        if !clickFirstRoles.contains(target.role),
           AXUIElementPerformAction(target.element, kAXPressAction as CFString) == .success {
            return
        }
        click(at: CGPoint(x: target.frame.midX, y: target.frame.midY))
    }

    /// 지정 좌표(CG)에 실제 클릭 합성 (포인터 이동 포함)
    static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type,
                    mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }

    /// 포인터만 이동 (CG 좌표)
    static func moveCursor(to point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
