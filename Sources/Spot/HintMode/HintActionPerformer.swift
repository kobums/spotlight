import ApplicationServices

/// 선택된 요소를 실행한다. AXPress를 우선 시도하고, 실패하거나
/// 캐럿 위치가 중요한 텍스트 입력류는 실제 클릭 이벤트를 합성한다.
enum HintActionPerformer {
    private static let clickFirstRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField"]

    static func perform(_ target: HintTarget) {
        if !clickFirstRoles.contains(target.role),
           AXUIElementPerformAction(target.element, kAXPressAction as CFString) == .success {
            return
        }
        postClick(at: CGPoint(x: target.frame.midX, y: target.frame.midY))
    }

    private static func postClick(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type,
                    mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
}
