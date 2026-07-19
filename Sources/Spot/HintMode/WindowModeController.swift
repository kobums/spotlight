import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 창 모드: 단일 키로 최전면 창을 배치한다 (Rectangle 대체).
/// 모드가 유지되어 연속 조작 가능 — "H(왼쪽 절반) → H(⅔) → K(상단)" 식.
final class WindowModeController: NSObject, NSWindowDelegate {
    private final class HUDPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private var panel: HUDPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        cancel()

        let screen = HintTargetCollector.focusedWindowFrame().flatMap { frame in
            let nsRect = ScreenCoords.cgToNS(frame)
            return NSScreen.screens.first { $0.frame.intersects(nsRect) }
        } ?? NSScreen.main
        guard let screen else { return }

        let hudSize = NSSize(width: 640, height: 44)
        let origin = NSPoint(
            x: screen.frame.midX - hudSize.width / 2,
            y: screen.frame.minY + 60
        )
        let panel = HUDPanel(
            contentRect: NSRect(origin: origin, size: hudSize),
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
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: WindowHUDView())
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func cancel() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        cancel()
    }

    // MARK: - 키 입력

    private func handle(_ event: NSEvent) -> NSEvent? {
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
        default: break
        }
        return nil // 창 모드 중에는 모든 키를 삼킨다
    }
}

private struct WindowHUDView: View {
    var body: some View {
        Text("창   H/J/K/L 절반(반복 ⅔·⅓)   Y/U/B/N 코너   M 최대   C 중앙   R 복원   Esc 종료")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
