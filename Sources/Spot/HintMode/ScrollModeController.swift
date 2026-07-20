import AppKit
import Carbon.HIToolbox
import SwiftUI

/// HJKL 스크롤 모드. 포인터를 최전면 창 중앙으로 옮긴 뒤 스크롤 휠 이벤트를 합성한다.
/// 키 입력은 하단 HUD 패널이 키 윈도우가 되어 삼킨다 — 대상 앱에는 스크롤만 전달된다.
final class ScrollModeController: ModeOverlayController {
    func show() {
        // 스크롤 이벤트는 포인터 아래 창으로 가므로, 포인터를 대상 창 중앙으로 이동
        let windowFrame = HintTargetCollector.focusedWindowFrame()
        if let windowFrame {
            HintActionPerformer.moveCursor(to: CGPoint(x: windowFrame.midX, y: windowFrame.midY))
        }

        let screen = windowFrame.flatMap { frame in
            let nsRect = ScreenCoords.cgToNS(frame)
            return NSScreen.screens.first { $0.frame.intersects(nsRect) }
        } ?? NSScreen.main
        guard let screen else { return }

        let hudSize = NSSize(width: 420, height: 44)
        let origin = NSPoint(
            x: screen.frame.midX - hudSize.width / 2,
            y: screen.frame.minY + 60
        )
        present(frame: NSRect(origin: origin, size: hudSize),
                view: NSHostingView(rootView: ScrollHUDView()))
    }

    // MARK: - 키 입력

    override func handle(_ event: NSEvent) -> NSEvent? {
        let line: Int32 = 3
        let halfPage: Int32 = 18
        switch Int(event.keyCode) {
        case kVK_Escape: cancel()
        case kVK_ANSI_J: postScroll(dy: -line)
        case kVK_ANSI_K: postScroll(dy: line)
        case kVK_ANSI_H: postScroll(dx: line)
        case kVK_ANSI_L: postScroll(dx: -line)
        case kVK_ANSI_D: postScroll(dy: -halfPage)
        case kVK_ANSI_U: postScroll(dy: halfPage)
        default: break
        }
        return nil // 스크롤 모드 중에는 모든 키를 삼킨다
    }

    // MARK: - 이벤트 합성

    private func postScroll(dy: Int32 = 0, dx: Int32 = 0) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(scrollWheelEvent2Source: source, units: .line,
                wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }
}

private struct ScrollHUDView: View {
    var body: some View {
        Text("스크롤   H ←   J ↓   K ↑   L →    D/U 반 페이지    Esc 종료")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
