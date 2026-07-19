import AppKit
import ApplicationServices

/// 창 모드·전역 단축키에서 실행하는 창 배치 액션.
enum WindowAction {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, maximizeHeight, center, restore
    case smaller, larger
    case nextDisplay, previousDisplay
}

/// 최전면 창의 프레임을 계산해 AX로 적용한다 (Rectangle 방식).
/// 계산은 메뉴바·Dock을 뺀 visibleFrame 기준, 좌표는 CG(주 화면 좌상단 원점).
final class WindowManager {
    static let shared = WindowManager()

    /// 절반 액션의 같은 키 반복 사이클: ½ → ⅔ → ⅓
    private static let cycleFractions: [CGFloat] = [1 / 2, 2 / 3, 1 / 3]
    /// 현재 프레임과 후보 프레임의 일치 판정 허용 오차 (px)
    private static let tolerance: CGFloat = 5

    /// 창별 첫 스냅 이전 프레임 — R(복원)용. AXUIElement는 CFEqual로 비교한다.
    private var savedFrames: [(window: AXUIElement, frame: CGRect)] = []
    private let maxSaved = 20

    func perform(_ action: WindowAction) {
        guard let app = HintTargetCollector.frontmostApp() else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let (window, current) = focusedWindow(of: appElement) else { return }

        if action == .restore {
            if let index = savedIndex(of: window) {
                let original = savedFrames[index].frame
                savedFrames.remove(at: index)
                setFrame(original, for: window, appElement: appElement)
            }
            return
        }

        guard let visible = visibleFrameCG(around: current) else { return }
        let target = targetFrame(for: action, current: current, visible: visible)

        if savedIndex(of: window) == nil {
            savedFrames.append((window, current))
            if savedFrames.count > maxSaved { savedFrames.removeFirst() }
        }
        setFrame(target, for: window, appElement: appElement)
    }

    // MARK: - 프레임 계산

    private func targetFrame(for action: WindowAction, current: CGRect, visible: CGRect) -> CGRect {
        func slice(_ fraction: CGFloat, from edge: WindowAction) -> CGRect {
            switch edge {
            case .leftHalf:
                return CGRect(x: visible.minX, y: visible.minY,
                              width: visible.width * fraction, height: visible.height)
            case .rightHalf:
                return CGRect(x: visible.maxX - visible.width * fraction, y: visible.minY,
                              width: visible.width * fraction, height: visible.height)
            case .topHalf:
                return CGRect(x: visible.minX, y: visible.minY,
                              width: visible.width, height: visible.height * fraction)
            case .bottomHalf:
                return CGRect(x: visible.minX, y: visible.maxY - visible.height * fraction,
                              width: visible.width, height: visible.height * fraction)
            default:
                return visible
            }
        }

        switch action {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            // 현재 프레임이 사이클의 i번째와 일치하면 다음 단계로
            let candidates = Self.cycleFractions.map { slice($0, from: action) }
            if let matched = candidates.firstIndex(where: { approximatelyEqual($0, current) }) {
                return candidates[(matched + 1) % candidates.count]
            }
            return candidates[0]
        case .topLeft:
            return CGRect(x: visible.minX, y: visible.minY,
                          width: visible.width / 2, height: visible.height / 2)
        case .topRight:
            return CGRect(x: visible.midX, y: visible.minY,
                          width: visible.width / 2, height: visible.height / 2)
        case .bottomLeft:
            return CGRect(x: visible.minX, y: visible.midY,
                          width: visible.width / 2, height: visible.height / 2)
        case .bottomRight:
            return CGRect(x: visible.midX, y: visible.midY,
                          width: visible.width / 2, height: visible.height / 2)
        case .maximize:
            return visible
        case .maximizeHeight:
            return CGRect(x: current.minX, y: visible.minY,
                          width: current.width, height: visible.height)
        case .center:
            return CGRect(x: visible.midX - current.width / 2,
                          y: visible.midY - current.height / 2,
                          width: current.width, height: current.height)
        case .smaller, .larger:
            // 중심 유지한 채 양 축 ±30px (Rectangle 기본값), 가용 영역·최소 크기로 클램프
            let delta: CGFloat = action == .larger ? 30 : -30
            let width = min(max(current.width + delta, 200), visible.width)
            let height = min(max(current.height + delta, 150), visible.height)
            var frame = CGRect(x: current.midX - width / 2, y: current.midY - height / 2,
                               width: width, height: height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - height)
            return frame
        case .nextDisplay, .previousDisplay:
            let screens = NSScreen.screens
            guard screens.count > 1 else { return current }
            let nsCurrent = ScreenCoords.cgToNS(current)
            let index = screens.indices.max { a, b in
                intersectionArea(screens[a].frame, nsCurrent) < intersectionArea(screens[b].frame, nsCurrent)
            } ?? 0
            let offset = action == .nextDisplay ? 1 : screens.count - 1
            let targetVisible = ScreenCoords.nsToCG(screens[(index + offset) % screens.count].visibleFrame)
            // 원본 화면 내 상대 위치·크기를 비율로 유지하며 이동
            return CGRect(
                x: targetVisible.minX + (current.minX - visible.minX) / visible.width * targetVisible.width,
                y: targetVisible.minY + (current.minY - visible.minY) / visible.height * targetVisible.height,
                width: current.width / visible.width * targetVisible.width,
                height: current.height / visible.height * targetVisible.height)
        case .restore:
            return current // perform()에서 먼저 처리됨
        }
    }

    private func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= Self.tolerance && abs(a.minY - b.minY) <= Self.tolerance
            && abs(a.width - b.width) <= Self.tolerance && abs(a.height - b.height) <= Self.tolerance
    }

    /// 창과 교집합이 가장 큰 화면의 가용 영역(메뉴바·Dock 제외)을 CG 좌표로
    private func visibleFrameCG(around windowFrame: CGRect) -> CGRect? {
        let nsRect = ScreenCoords.cgToNS(windowFrame)
        let screen = NSScreen.screens.max { a, b in
            intersectionArea(a.frame, nsRect) < intersectionArea(b.frame, nsRect)
        } ?? NSScreen.main
        guard let screen else { return nil }
        return ScreenCoords.nsToCG(screen.visibleFrame)
    }

    private func intersectionArea(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let rect = a.intersection(b)
        return rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }

    // MARK: - AX 적용

    private func focusedWindow(of appElement: AXUIElement) -> (AXUIElement, CGRect)? {
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement
        guard let frame = frame(of: window) else { return nil }
        return (window, frame)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID(),
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement, appElement: AXUIElement) {
        // AXEnhancedUserInterface가 켜진 앱(힌트 모드가 Electron에 직접 켬)은 AX 이동이
        // 애니메이션되며 위치가 어긋난다 — 이동 동안만 끈다
        var enhancedRef: CFTypeRef?
        let hadEnhanced = AXUIElementCopyAttributeValue(
            appElement, "AXEnhancedUserInterface" as CFString, &enhancedRef) == .success
            && (enhancedRef as? Bool) == true
        if hadEnhanced {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }

        var position = frame.origin
        var size = frame.size
        if let positionValue = AXValueCreate(.cgPoint, &position),
           let sizeValue = AXValueCreate(.cgSize, &size) {
            // 앱의 최소 크기 클램프·화면 경계 걸침 대응 — position→size를 두 번 적용
            for _ in 0..<2 {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            }
        }

        if hadEnhanced {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    private func savedIndex(of window: AXUIElement) -> Int? {
        savedFrames.firstIndex { CFEqual($0.window, window) }
    }
}
