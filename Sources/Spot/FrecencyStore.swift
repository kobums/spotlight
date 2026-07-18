import Foundation

/// 선택 이력 기반 frecency 랭킹. 반감기 7일의 지수 감쇠 합.
final class FrecencyStore {
    static let shared = FrecencyStore()

    private var timestamps: [String: [TimeInterval]] = [:]
    private let store = JSONFileStore<[String: [TimeInterval]]>(filename: "frecency.json", saveDelay: 1.0)
    private let halfLife: TimeInterval = 7 * 24 * 3600
    private let maxTimestampsPerID = 50

    private init() {
        timestamps = store.load() ?? [:]
    }

    func recordSelection(id: String) {
        var list = timestamps[id] ?? []
        list.append(Date().timeIntervalSince1970)
        if list.count > maxTimestampsPerID { list.removeFirst(list.count - maxTimestampsPerID) }
        timestamps[id] = list
        store.scheduleSave(timestamps)
    }

    /// 0 이상. 방금 선택했으면 1점, 시간이 지날수록 감쇠.
    func boost(id: String) -> Double {
        guard let list = timestamps[id] else { return 0 }
        let now = Date().timeIntervalSince1970
        return list.reduce(0) { acc, t in
            acc + pow(2, -(now - t) / halfLife)
        }
    }
}
