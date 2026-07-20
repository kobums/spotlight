import CoreGraphics
import Foundation

/// DDC가 안 되는 모니터용 감마 소프트웨어 디밍.
///
/// 백라이트가 아니라 렌더링 최대치를 낮추는 방식 — MonitorControl의 폴백과 동일.
/// 감마는 설정한 프로세스가 종료되면 시스템이 원복하므로 Spot 상시 실행이 전제다.
/// 디스플레이 재구성(해상도 변경·재연결) 시 리셋되므로 콜백에서 재적용한다.
final class GammaDimmer {
    /// 화면이 완전히 검어져 조작 불능이 되는 것을 막는 하한
    static let minPercent = 10

    private var scales: [CGDirectDisplayID: Int] = [:]  // 100 = 원본

    func brightness(of display: CGDirectDisplayID) -> Int {
        scales[display] ?? 100
    }

    func setBrightness(_ percent: Int, of display: CGDirectDisplayID) {
        let clamped = max(Self.minPercent, min(100, percent))
        scales[display] = clamped
        apply(display: display, percent: clamped)
    }

    /// 디스플레이 재구성 후 저장된 스케일 재적용
    func reapplyAll() {
        for (display, percent) in scales {
            apply(display: display, percent: percent)
        }
    }

    func reset(_ display: CGDirectDisplayID) {
        scales[display] = nil
        CGDisplayRestoreColorSyncSettings()
        reapplyAll()  // 전체 리셋 후 다른 모니터 것만 되살린다
    }

    private func apply(display: CGDirectDisplayID, percent: Int) {
        let scale = CGGammaValue(percent) / 100
        CGSetDisplayTransferByFormula(display,
                                      0, scale, 1,   // R: min, max, gamma
                                      0, scale, 1,   // G
                                      0, scale, 1)   // B
    }
}
