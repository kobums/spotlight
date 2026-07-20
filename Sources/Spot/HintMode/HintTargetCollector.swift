import AppKit
import ApplicationServices

/// 힌트 라벨을 붙일 수 있는 화면 위의 요소.
struct HintTarget {
    let element: AXUIElement
    let role: String
    /// AXTitle 또는 AXDescription — 요소 이름 검색 모드에서 사용
    let name: String
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

    /// 유니버설 컨트롤 같은 백그라운드 프로세스가 frontmost로 잡히면
    /// 메뉴 막대를 소유한 실제 활성 앱으로 폴백
    static func frontmostApp() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.activationPolicy != .regular {
            return NSWorkspace.shared.menuBarOwningApplication ?? frontmost
        }
        return frontmost
    }

    /// 최전면 앱 포커스 창의 프레임 (CG 좌표). 스크롤 모드의 포인터 이동 목표.
    static func focusedWindowFrame() -> CGRect? {
        guard let app = frontmostApp(),
              let window = AX.focusedWindow(pid: app.processIdentifier) else { return nil }
        let (_, _, frame, _) = fetchAttributes(window)
        return frame
    }

    static func collectFrontmost() -> HintCollection? {
        guard let app = frontmostApp() else { return nil }
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

        func append(_ element: AXUIElement, role: String, name: String, frame: CGRect) {
            let key = "\(Int(frame.midX)),\(Int(frame.midY))"
            guard !seenCenters.contains(key) else { return }
            seenCenters.insert(key)
            targets.append(HintTarget(element: element, role: role, name: name, frame: frame))
        }

        func walk(_ element: AXUIElement, clip: CGRect, depth: Int) {
            guard depth < maxDepth, visited < maxVisited, targets.count < maxTargets else { return }
            visited += 1
            let (role, name, frame, children) = fetchAttributes(element)

            // 유효한 크기인데 클립 영역과 안 겹치면 스크롤 밖 서브트리 — 가지치기
            if let frame, frame.width > 1, frame.height > 1, !frame.intersects(clip) { return }

            if let role, let frame,
               actionableRoles.contains(role),
               frame.width > 2, frame.height > 2,
               clip.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                append(element, role: role, name: name, frame: frame)
            }

            // 닫힌 메뉴 아래로는 내려가지 않는다
            if role == "AXMenuBarItem" || role == "AXMenu" { return }
            for child in children {
                walk(child, clip: clip, depth: depth + 1)
            }
        }

        // 메뉴 막대 항목
        if let menuBar = AX.element(AX.attribute(appElement, kAXMenuBarAttribute as String)) {
            let (_, _, _, items) = fetchAttributes(menuBar)
            for item in items {
                let (role, name, frame, _) = fetchAttributes(item)
                if let frame, role == "AXMenuBarItem", frame.width > 2 {
                    append(item, role: "AXMenuBarItem", name: name, frame: frame)
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

    /// 요소 하나당 IPC 1회로 role·이름·frame·children을 한 번에 읽는다.
    private static func fetchAttributes(_ element: AXUIElement)
        -> (role: String?, name: String, frame: CGRect?, children: [AXUIElement]) {
        var valuesRef: CFArray?
        let attributes = [
            kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
            kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
        ] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef) == .success,
              let values = valuesRef as? [AnyObject], values.count == 6 else {
            return (nil, "", nil, [])
        }

        let role = values[0] as? String
        let title = (values[1] as? String) ?? ""
        let description = (values[2] as? String) ?? ""
        let name = title.isEmpty ? description : title

        var frame: CGRect?
        if let origin = AX.point(values[3]), let size = AX.size(values[4]) {
            frame = CGRect(origin: origin, size: size)
        }

        var children: [AXUIElement] = []
        if CFGetTypeID(values[5]) == CFArrayGetTypeID(), let array = values[5] as? [AnyObject] {
            children = array.compactMap(AX.element)
        }
        return (role, name, frame, children)
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
