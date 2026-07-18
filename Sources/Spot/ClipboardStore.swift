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
    private let store = JSONFileStore<[Entry]>(filename: "clipboard.json", saveDelay: 2.0)

    private let maxEntries = 300

    /// Spot 자신이 클립보드에 쓸 때 히스토리 중복 저장 방지
    private var ignoreNextChange = false

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        entries = store.load() ?? []
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Spot이 클립보드에 쓰는 유일한 경로. 히스토리 최상단에도 기록한다.
    func copy(_ text: String) {
        ignoreNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        record(text)
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
        record(text)
    }

    private func record(_ text: String) {
        entries.removeAll { $0.text == text }
        entries.insert(Entry(text: text, date: Date()), at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        store.scheduleSave(entries)
    }
}
