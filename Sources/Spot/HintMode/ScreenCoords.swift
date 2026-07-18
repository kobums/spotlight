import AppKit

/// AX API는 주 화면 좌상단 원점(y 아래 방향)의 CG 좌표를, AppKit은 좌하단 원점을 쓴다.
/// 두 공간은 x가 같고 y만 주 화면 높이 기준으로 뒤집힌다 — 변환식은 양방향이 동일하다.
enum ScreenCoords {
    private static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    static func nsToCG(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cgToNS(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
