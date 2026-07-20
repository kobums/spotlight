import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 창 모드: 단일 키로 최전면 창을 배치한다 (Rectangle 대체).
/// 모드가 유지되어 연속 조작 가능 — "H(왼쪽 절반) → H(⅔) → K(상단)" 식.
final class WindowModeController: ModeOverlayController {
    func show() {
        let screen = HintTargetCollector.focusedWindowFrame().flatMap { frame in
            let nsRect = ScreenCoords.cgToNS(frame)
            return NSScreen.screens.first { $0.frame.intersects(nsRect) }
        } ?? NSScreen.main
        guard let screen else { return }

        let hudSize = NSSize(width: 780, height: 44)
        let origin = NSPoint(
            x: screen.frame.midX - hudSize.width / 2,
            y: screen.frame.minY + 60
        )
        present(frame: NSRect(origin: origin, size: hudSize),
                view: NSHostingView(rootView: WindowHUDView()))
    }

    // MARK: - 키 입력

    override func handle(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case kVK_Escape: cancel()
        case kVK_ANSI_H: WindowManager.shared.perform(.leftHalf)
        case kVK_ANSI_L: WindowManager.shared.perform(.rightHalf)
        case kVK_ANSI_K: WindowManager.shared.perform(.topHalf)
        case kVK_ANSI_J: WindowManager.shared.perform(.bottomHalf)
        case kVK_ANSI_Y: WindowManager.shared.perform(.topLeft)
        case kVK_ANSI_U: WindowManager.shared.perform(.topRight)
        case kVK_ANSI_B: WindowManager.shared.perform(.bottomLeft)
        case kVK_ANSI_N: WindowManager.shared.perform(.bottomRight)
        case kVK_ANSI_M: WindowManager.shared.perform(.maximize)
        case kVK_ANSI_C: WindowManager.shared.perform(.center)
        case kVK_ANSI_R: WindowManager.shared.perform(.restore)
        case kVK_ANSI_Minus: WindowManager.shared.perform(.smaller)
        case kVK_ANSI_Equal: WindowManager.shared.perform(.larger)
        case kVK_ANSI_LeftBracket: WindowManager.shared.perform(.previousDisplay)
        case kVK_ANSI_RightBracket: WindowManager.shared.perform(.nextDisplay)
        default: break
        }
        return nil // 창 모드 중에는 모든 키를 삼킨다
    }
}

private struct WindowHUDView: View {
    var body: some View {
        Text("창   H/J/K/L 절반(반복 ⅔·⅓)   Y/U/B/N 코너   M 최대   C 중앙   -/= 크기   [/] 디스플레이   R 복원   Esc 종료")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
