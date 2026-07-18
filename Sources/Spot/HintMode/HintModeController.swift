import AppKit

/// 힌트 모드 오케스트레이터: 권한 확인 → 백그라운드에서 AX 트리 수집 → 오버레이 표시 → 선택 실행.
final class HintModeController {
    private let overlay = HintOverlayController()
    private var isCollecting = false

    func toggle() {
        if overlay.isVisible {
            overlay.cancel()
            return
        }
        guard AccessibilityPermission.ensureTrusted() else { return }
        guard !isCollecting else { return }
        isCollecting = true

        // AX 트리 순회는 IPC라 느릴 수 있어 메인 스레드를 막지 않는다
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let collection = HintTargetCollector.collectFrontmost()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCollecting = false
                guard let collection else { return }
                self.overlay.show(targets: collection.targets, on: collection.screen) { target in
                    HintActionPerformer.perform(target)
                }
            }
        }
    }
}
