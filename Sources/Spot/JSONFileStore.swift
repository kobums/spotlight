import Foundation

/// Application Support/Spot/<파일명>에 Codable 값을 JSON으로 저장하는 헬퍼.
/// 저장은 디바운스되어 마지막 호출 후 지연 시간이 지나면 한 번만 기록된다.
final class JSONFileStore<Value: Codable> {
    private let fileURL: URL
    private let saveDelay: TimeInterval
    private var saveWorkItem: DispatchWorkItem?

    init(filename: String, saveDelay: TimeInterval) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Spot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(filename)
        self.saveDelay = saveDelay
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    /// 현재 값의 스냅숏을 지연 저장. 연속 호출되면 마지막 스냅숏만 기록된다.
    func scheduleSave(_ value: Value) {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [fileURL] in
            if let data = try? JSONEncoder().encode(value) {
                try? data.write(to: fileURL)
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: item)
    }
}
