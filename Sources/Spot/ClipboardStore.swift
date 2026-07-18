import AppKit

/// NSPasteboard 폴링 기반 클립보드 히스토리. 텍스트만 저장, 최대 300개, 디스크 영속.
final class ClipboardStore {
    static let shared = ClipboardStore()

    struct Entry: Codable {
        let text: String
        let date: Date
    }

    private(set) var entries: [Entry] = []
    private var lastChangeCount: Int
    private var timer: Timer?
    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    /// Spot 자신이 클립보드에 쓸 때 히스토리 중복 저장 방지
    var ignoreNextChange = false

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("clipboard.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }
        guard let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count < 100_000 else { return }

        entries.removeAll { $0.text == text }
        entries.insert(Entry(text: text, date: Date()), at: 0)
        if entries.count > 300 { entries.removeLast(entries.count - 300) }
        scheduleSave()
    }

    func copyToPasteboard(_ text: String) {
        ignoreNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let data = try? JSONEncoder().encode(self.entries) {
                try? data.write(to: self.fileURL)
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }
}
