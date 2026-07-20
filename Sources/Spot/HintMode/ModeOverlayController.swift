import AppKit

/// 키를 삼키는 모드 오버레이(힌트·그리드·스크롤 HUD·창 HUD) 공통 기반.
///
/// nonactivating 패널을 키 윈도우로 띄워 키 입력만 받고 클릭은 통과시킨다.
/// 키 포커스를 잃으면(다른 곳 클릭) 자동 취소. 서브클래스는 present(frame:view:)로
/// 띄우고 handle(_:)로 키를 처리한다.
class ModeOverlayController: NSObject, NSWindowDelegate {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private(set) var panel: NSPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 패널 생성·표시 + 키 모니터 설치 (이미 떠 있으면 먼저 취소)
    func present(frame: NSRect, view: NSView) {
        cancel()

        let panel = Panel(
            contentRect: frame,
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
        panel.contentView = view
        panel.setFrame(frame, display: true)
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
        didCancel()
    }

    /// 서브클래스 훅 — cancel 시 추가 정리 (콜백 해제 등)
    func didCancel() {}

    /// 서브클래스가 키를 처리한다. nil 반환 = 이벤트 삼킴 (기본).
    func handle(_ event: NSEvent) -> NSEvent? { nil }

    func windowDidResignKey(_ notification: Notification) {
        cancel()
    }
}
