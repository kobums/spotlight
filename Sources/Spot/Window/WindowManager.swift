import AppKit
import ApplicationServices

/// 창 모드·전역 단축키에서 실행하는 창 배치 액션.
/// rawValue는 설정 파일의 단축키 키로 쓰이므로 바꾸면 기존 설정과 호환이 깨진다.
enum WindowAction: String, CaseIterable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, maximizeHeight, center, restore
    case smaller, larger
    case nextDisplay, previousDisplay

    var displayName: String {
        switch self {
        case .leftHalf: return "왼쪽 절반"
        case .rightHalf: return "오른쪽 절반"
        case .topHalf: return "위쪽 절반"
        case .bottomHalf: return "아래쪽 절반"
        case .topLeft: return "왼쪽 위"
        case .topRight: return "오른쪽 위"
        case .bottomLeft: return "왼쪽 아래"
        case .bottomRight: return "오른쪽 아래"
        case .maximize: return "최대화"
        case .maximizeHeight: return "높이 최대화"
        case .center: return "가운데"
        case .restore: return "복원"
        case .smaller: return "작게"
        case .larger: return "크게"
        case .nextDisplay: return "다음 디스플레이"
        case .previousDisplay: return "이전 디스플레이"
        }
    }
}

/// 최전면 창의 프레임을 계산해 AX로 적용한다 (Rectangle 방식).
/// 계산은 메뉴바·Dock을 뺀 visibleFrame 기준, 좌표는 CG(주 화면 좌상단 원점).
final class WindowManager {
    static let shared = WindowManager()

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
        let gap = CGFloat(WindowSettingsStore.shared.settings.gap)

        /// 창 사이 간격 적용: 화면 가장자리에 닿는 변은 gap, 창끼리 맞닿는 안쪽 변은 gap/2
        func gapped(_ rect: CGRect) -> CGRect {
            guard gap > 0 else { return rect }
            let left = abs(rect.minX - visible.minX) < 1 ? gap : gap / 2
            let right = abs(rect.maxX - visible.maxX) < 1 ? gap : gap / 2
            let top = abs(rect.minY - visible.minY) < 1 ? gap : gap / 2
            let bottom = abs(rect.maxY - visible.maxY) < 1 ? gap : gap / 2
            return CGRect(x: rect.minX + left, y: rect.minY + top,
                          width: rect.width - left - right, height: rect.height - top - bottom)
        }

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
            let fractions = WindowSettingsStore.shared.settings.cycleFractions.map { CGFloat($0) }
            let candidates = (fractions.isEmpty ? [0.5] : fractions).map { gapped(slice($0, from: action)) }
            if let matched = candidates.firstIndex(where: { approximatelyEqual($0, current) }) {
                return candidates[(matched + 1) % candidates.count]
            }
            return candidates[0]
        case .topLeft:
            return gapped(CGRect(x: visible.minX, y: visible.minY,
                                 width: visible.width / 2, height: visible.height / 2))
        case .topRight:
            return gapped(CGRect(x: visible.midX, y: visible.minY,
                                 width: visible.width / 2, height: visible.height / 2))
        case .bottomLeft:
            return gapped(CGRect(x: visible.minX, y: visible.midY,
                                 width: visible.width / 2, height: visible.height / 2))
        case .bottomRight:
            return gapped(CGRect(x: visible.midX, y: visible.midY,
                                 width: visible.width / 2, height: visible.height / 2))
        case .maximize:
            return gapped(visible)
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
