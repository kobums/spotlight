import Foundation

/// 선택 이력 기반 frecency 랭킹. 반감기 7일의 지수 감쇠 합.
final class FrecencyStore {
    static let shared = FrecencyStore()

    private var timestamps: [String: [TimeInterval]] = [:]
    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private let halfLife: TimeInterval = 7 * 24 * 3600

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("frecency.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: [TimeInterval]].self, from: data) {
            timestamps = decoded
        }
    }

    func recordSelection(id: String) {
        var list = timestamps[id] ?? []
        list.append(Date().timeIntervalSince1970)
        if list.count > 50 { list.removeFirst(list.count - 50) }
        timestamps[id] = list
        scheduleSave()
    }

    /// 0 이상. 방금 선택했으면 1점, 시간이 지날수록 감쇠.
    func boost(id: String) -> Double {
        guard let list = timestamps[id] else { return 0 }
        let now = Date().timeIntervalSince1970
        return list.reduce(0) { acc, t in
            acc + pow(2, -(now - t) / halfLife)
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let data = try? JSONEncoder().encode(self.timestamps) {
                try? data.write(to: self.fileURL)
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}
