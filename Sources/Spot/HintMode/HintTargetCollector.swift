import AppKit
import ApplicationServices

/// 힌트 라벨을 붙일 수 있는 화면 위의 요소.
struct HintTarget {
    let element: AXUIElement
    let role: String
    let title: String
    /// CG(주 화면 좌상단 원점) 전역 좌표
    let frame: CGRect
}

struct HintCollection {
    let targets: [HintTarget]
    let screen: NSScreen
}

/// 최전면 앱의 접근성 트리를 순회해 클릭 가능한 요소를 모은다.
/// AX 호출은 프로세스 간 IPC라 느리므로 배치 조회 + 가지치기 + 상한으로 시간을 제한한다.
enum HintTargetCollector {
    private static let actionableRoles: Set<String> = [
        "AXButton", "AXLink", "AXMenuButton", "AXMenuItem", "AXMenuBarItem",
        "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXComboBox",
        "AXTextField", "AXTextArea", "AXSearchField", "AXSlider", "AXIncrementor",
        "AXDisclosureTriangle", "AXTabButton", "AXCell", "AXColorWell", "AXSwitch",
    ]
    private static let maxTargets = 400
    private static let maxVisited = 4000
    private static let maxDepth = 40

    static func collectFrontmost() -> HintCollection? {
        // 유니버설 컨트롤 같은 백그라운드 프로세스가 frontmost로 잡히면
        // 메뉴 막대를 소유한 실제 활성 앱으로 폴백
        var frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.activationPolicy != .regular {
            frontmost = NSWorkspace.shared.menuBarOwningApplication ?? frontmost
        }
        guard let app = frontmost else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        enableChromiumAccessibility(appElement)

        var result = collect(from: appElement)
        if result.targets.isEmpty {
            // Electron/Chromium은 플래그 설정 직후 첫 순회가 빈 트리일 수 있다 — 잠시 후 1회 재시도
            Thread.sleep(forTimeInterval: 0.25)
            result = collect(from: appElement)
        }
        guard !result.targets.isEmpty else { return nil }

        let screen = result.primaryWindowFrame.flatMap(screen(for:)) ?? NSScreen.main
        guard let screen else { return nil }
        let screenCG = ScreenCoords.nsToCG(screen.frame)
        let onScreen = result.targets.filter { screenCG.intersects($0.frame) }
        return HintCollection(targets: Array(onScreen.prefix(maxTargets)), screen: screen)
    }

    // MARK: - 순회

    private static func collect(from appElement: AXUIElement) -> (targets: [HintTarget], primaryWindowFrame: CGRect?) {
        var targets: [HintTarget] = []
        var seenCenters = Set<String>()
        var visited = 0
        var primaryWindowFrame: CGRect?

        func append(_ element: AXUIElement, role: String, title: String?, frame: CGRect) {
            let key = "\(Int(frame.midX)),\(Int(frame.midY))"
            guard !seenCenters.contains(key) else { return }
            seenCenters.insert(key)
            targets.append(HintTarget(element: element, role: role, title: title ?? "", frame: frame))
        }

        func walk(_ element: AXUIElement, clip: CGRect, depth: Int) {
            guard depth < maxDepth, visited < maxVisited, targets.count < maxTargets else { return }
            visited += 1
            let (role, title, frame, children) = fetchAttributes(element)

            // 유효한 크기인데 클립 영역과 안 겹치면 스크롤 밖 서브트리 — 가지치기
            if let frame, frame.width > 1, frame.height > 1, !frame.intersects(clip) { return }

            if let role, let frame,
               actionableRoles.contains(role),
               frame.width > 2, frame.height > 2,
               clip.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                append(element, role: role, title: title, frame: frame)
            }

            // 닫힌 메뉴 아래로는 내려가지 않는다
            if role == "AXMenuBarItem" || role == "AXMenu" { return }
            for child in children {
                walk(child, clip: clip, depth: depth + 1)
            }
        }

        // 메뉴 막대 항목
        var menuBarRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
           let menuBarRef, CFGetTypeID(menuBarRef) == AXUIElementGetTypeID() {
            let (_, _, _, items) = fetchAttributes(menuBarRef as! AXUIElement)
            for item in items {
                let (role, title, frame, _) = fetchAttributes(item)
                if let frame, role == "AXMenuBarItem", frame.width > 2 {
                    append(item, role: "AXMenuBarItem", title: title, frame: frame)
                }
            }
        }

        // 창 순회
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return (targets, primaryWindowFrame)
        }
        for window in windows {
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               (minimizedRef as? Bool) == true { continue }

            let (_, _, windowFrame, _) = fetchAttributes(window)
            guard let windowFrame, windowFrame.width > 1, windowFrame.height > 1 else { continue }
            if primaryWindowFrame == nil { primaryWindowFrame = windowFrame }
            walk(window, clip: windowFrame, depth: 0)
        }
        return (targets, primaryWindowFrame)
    }

    /// 요소 하나당 IPC 1회로 role·title·frame·children을 한 번에 읽는다.
    private static func fetchAttributes(_ element: AXUIElement)
        -> (role: String?, title: String?, frame: CGRect?, children: [AXUIElement]) {
        var valuesRef: CFArray?
        let attributes = [
            kAXRoleAttribute, kAXTitleAttribute,
            kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
        ] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef) == .success,
              let values = valuesRef as? [AnyObject], values.count == 5 else {
            return (nil, nil, nil, [])
        }

        let role = values[0] as? String
        let title = values[1] as? String
        var frame: CGRect?
        if let origin = axPoint(values[2]), let size = axSize(values[3]) {
            frame = CGRect(origin: origin, size: size)
        }

        var children: [AXUIElement] = []
        if CFGetTypeID(values[4]) == CFArrayGetTypeID(), let array = values[4] as? [AnyObject] {
            children = array.compactMap { child in
                guard CFGetTypeID(child) == AXUIElementGetTypeID() else { return nil }
                return (child as! AXUIElement)
            }
        }
        return (role, title, frame, children)
    }

    private static func axPoint(_ value: AnyObject?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func axSize(_ value: AnyObject?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    /// Electron/Chromium 앱은 보조 기술이 감지될 때만 AX 트리를 만든다.
    /// AXManualAccessibility(신형)와 AXEnhancedUserInterface(구형)를 모두 켠다.
    /// 주의: AXEnhancedUserInterface는 일부 앱에서 창 이동 애니메이션에 부작용이 있다.
    private static func enableChromiumAccessibility(_ appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func screen(for cgRect: CGRect) -> NSScreen? {
        let nsRect = ScreenCoords.cgToNS(cgRect)
        return NSScreen.screens.max { a, b in
            area(a.frame.intersection(nsRect)) < area(b.frame.intersection(nsRect))
        }
    }

    private static func area(_ rect: NSRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }
}
