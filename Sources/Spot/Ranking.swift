import Foundation

/// 결과 랭킹에 쓰는 점수 스케일 전체. 랭킹 튜닝은 이 파일에서만 한다.
///
/// 고정 점수(모드성 결과)는 fuzzy 점수 대역(대략 -1 ~ 5)과 겹치지 않게 크게 띄운다:
/// 계산(1000) > 웹 프리픽스(900) > 클립보드(500) > 완전 일치 앱(100) > 액션(50)
/// > fuzzy 대역 > 웹 폴백(-1000, 항상 마지막)
enum Score {
    static let calculator: Double = 1000
    static let webPrefix: Double = 900
    static let clipboardTop: Double = 500   // 이후 -index로 최신순 유지
    static let webFallback: Double = -1000

    static let appExact: Double = 100
    static let appBonus: Double = 2.0       // 앱은 기본 가중치 우대
    static let actionExact: Double = 50
    static let actionBonus: Double = 0.5
    static let settingsExact: Double = 90    // 완전 일치 앱(100)보다는 낮게
    static let settingsBonus: Double = 1.5   // 앱(2.0)보다 낮은 우대
    static let fileExact: Double = 3.0
    static let filePenalty: Double = -0.5   // 파일은 앱보다 낮게

    static let frecencyWeight: Double = 2.0
}
