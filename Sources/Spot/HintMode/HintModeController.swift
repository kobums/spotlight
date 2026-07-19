import AppKit

/// 힌트 모드 오케스트레이터: 권한 확인 → 백그라운드에서 AX 트리 수집 → 오버레이 표시 → 선택 실행.
/// ⌃Space 순환: 힌트 모드 → (한 번 더 또는 Tab) 스크롤 모드 → 종료.
/// 힌트 모드에서 "/" → 그리드 모드, "." → 창 모드. 수집 결과가 없는 앱은 자동으로 그리드 폴백.
final class HintModeController {
    private let overlay = HintOverlayController()
    private let scrollMode = ScrollModeController()
    private let gridMode = GridModeController()
    private let windowMode = WindowModeController()
    private var isCollecting = false

    init() {
        overlay.onSwitchToScrollMode = { [weak self] in
            guard let self else { return }
            self.overlay.cancel()
            self.scrollMode.show()
        }
        overlay.onSwitchToGridMode = { [weak self] in
            guard let self else { return }
            self.overlay.cancel()
            self.gridMode.show()
        }
        overlay.onSwitchToWindowMode = { [weak self] in
            guard let self else { return }
            self.overlay.cancel()
            self.windowMode.show()
        }
    }

    func toggle() {
        if windowMode.isVisible {
            windowMode.cancel()
            return
        }
        if gridMode.isVisible {
            gridMode.cancel()
            return
        }
        if scrollMode.isVisible {
            scrollMode.cancel()
            return
        }
        if overlay.isVisible {
            overlay.cancel()
            scrollMode.show()
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
                guard let collection else {
                    // 접근성 정보가 없는 앱 — 그리드 모드로 폴백
                    self.gridMode.show()
                    return
                }
                self.overlay.show(targets: collection.targets, on: collection.screen) { target in
                    HintActionPerformer.perform(target)
                }
            }
        }
    }
}
