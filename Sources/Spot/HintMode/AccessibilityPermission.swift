import ApplicationServices

/// 손쉬운 사용(Accessibility) 권한. AX 트리 읽기와 이벤트 합성 모두 이 권한이 필요하다.
enum AccessibilityPermission {
    /// 권한이 있으면 true. 없으면 시스템 설정으로 유도하는 프롬프트를 띄우고 false.
    @discardableResult
    static func ensureTrusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        return false
    }
}
