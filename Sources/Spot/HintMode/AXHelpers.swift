import ApplicationServices

/// AX API가 돌려주는 CFTypeRef의 안전 캐스트와 자주 쓰는 조회 모음.
/// CFTypeID 확인 후 캐스트하는 것이 CF 타입을 다루는 유일하게 안전한 경로다.
enum AX {
    static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func point(_ value: AnyObject?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ value: AnyObject?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    static func rect(_ value: AnyObject?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    /// 속성 1개 조회 (IPC 1회 — 여러 개면 AXUIElementCopyMultipleAttributeValues 사용)
    static func attribute(_ element: AXUIElement, _ key: String) -> AnyObject? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success else { return nil }
        return ref
    }

    /// 창/요소의 프레임 (CG 좌표) — position·size 각각 조회
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(attribute(element, kAXPositionAttribute as String)),
              let size = size(attribute(element, kAXSizeAttribute as String)) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// 앱의 포커스 창
    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        return element(attribute(appElement, kAXFocusedWindowAttribute as String))
    }
}
