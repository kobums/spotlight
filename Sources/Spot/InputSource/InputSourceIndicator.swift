import AppKit
import ApplicationServices
import SwiftUI

/// 입력 소스 배지("한"/"A")를 캐럿 근처에 잠깐 표시한다.
///
/// 키 입력을 받지 않는 순수 표시용 오버레이 — 키 윈도우가 되지 않고 클릭도 통과한다.
/// 캐럿 위치는 AX로 읽고(보안 입력 등으로 실패하면 마우스 포인터 옆 폴백).
final class InputSourceIndicator {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(badge: String, korean: Bool, duration: Double = 1.0) {
        let position = caretPositionNS() ?? pointerPositionNS()

        let size = NSSize(width: 34, height: 34)
        let origin = NSPoint(x: position.x + 12, y: position.y - size.height - 6)

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NSPanel(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        panel.contentView = NSHostingView(rootView: IndicatorView(badge: badge, korean: korean))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: - 위치

    /// 포커스된 텍스트 요소의 캐럿 위치 (NS 좌표). 실패하면 nil.
    private func caretPositionNS() -> NSPoint? {
        guard let app = HintTargetCollector.frontmostApp() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused, kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.width >= 0,
              rect != .zero else { return nil }
        // CG(좌상단 원점) → NS(좌하단 원점), 캐럿 하단 기준
        let ns = ScreenCoords.cgToNS(rect)
        return NSPoint(x: ns.minX, y: ns.minY)
    }

    private func pointerPositionNS() -> NSPoint {
        NSEvent.mouseLocation
    }
}

private struct IndicatorView: View {
    let badge: String
    let korean: Bool

    var body: some View {
        Text(badge)
            .font(.system(size: 15, weight: .heavy))
            .foregroundColor(korean ? .black : .white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(korean ? Color(red: 1.0, green: 0.87, blue: 0.4) : Color(white: 0.25))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
