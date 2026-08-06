import AppKit

/// NSPasteboard 폴링 기반 클립보드 히스토리. 텍스트·이미지 저장, 고정(pin) 지원.
/// 텍스트는 JSON에, 이미지는 Application Support/Spot/clipboard-images/에 PNG로 저장.
/// 고정 안 된 항목은 최대 300개 유지, 고정 항목은 정리 대상에서 제외.
final class ClipboardStore {
    static let shared = ClipboardStore()

    struct Entry: Codable {
        let text: String          // 이미지 항목이면 "이미지 1200×800" 같은 표시용 텍스트
        let date: Date
        var pinned: Bool
        var imageFile: String?    // 이미지 항목이면 PNG 파일명

        var isImage: Bool { imageFile != nil }

        init(text: String, date: Date, pinned: Bool = false, imageFile: String? = nil) {
            self.text = text
            self.date = date
            self.pinned = pinned
            self.imageFile = imageFile
        }

        // 구버전 항목({text, date})과의 호환 — 없는 필드는 기본값
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            date = try container.decode(Date.self, forKey: .date)
            pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
            imageFile = try container.decodeIfPresent(String.self, forKey: .imageFile)
        }
    }

    private(set) var entries: [Entry] = []
    private var lastChangeCount: Int
    private var timer: Timer?
    private let store = JSONFileStore<[Entry]>(filename: "clipboard.json", saveDelay: 2.0)

    private let maxEntries = 300
    private let maxImageBytes = 20 * 1024 * 1024

    /// Spot 자신이 클립보드에 쓸 때 히스토리 중복 저장 방지
    private var ignoreNextChange = false

    private let imagesDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Spot/clipboard-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        entries = store.load() ?? []
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Spot이 텍스트를 클립보드에 쓰는 유일한 경로. 히스토리 최상단에도 기록한다.
    func copy(_ text: String) {
        ignoreNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        record(text)
    }

    /// 히스토리 항목을 클립보드로 — 이미지 항목이면 이미지 데이터를 쓴다
    func copyEntry(_ entry: Entry) {
        if let file = entry.imageFile {
            guard let image = NSImage(contentsOf: imagesDir.appendingPathComponent(file)) else { return }
            ignoreNextChange = true
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
            touch(entry)
        } else {
            copy(entry.text)
        }
    }

    /// 고정 토글 — 반환값은 토글 후 상태
    @discardableResult
    func togglePin(_ entry: Entry) -> Bool {
        guard let index = entries.firstIndex(where: { $0.date == entry.date && $0.text == entry.text }) else {
            return false
        }
        entries[index].pinned.toggle()
        store.scheduleSave(entries)
        return entries[index].pinned
    }

    /// 항목의 이미지 썸네일 (26pt 행 아이콘용, 캐시)
    func thumbnail(for entry: Entry) -> NSImage? {
        guard let file = entry.imageFile else { return nil }
        if let cached = thumbnailCache[file] { return cached }
        guard let image = NSImage(contentsOf: imagesDir.appendingPathComponent(file)) else { return nil }
        let side: CGFloat = 52
        let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        thumb.unlockFocus()
        thumbnailCache[file] = thumb
        return thumb
    }

    private var thumbnailCache: [String: NSImage] = [:]

    // MARK: - 폴링

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }
        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           text.count < 100_000 {
            record(text)
        } else if let image = NSImage(pasteboard: pb) {
            recordImage(image)
        }
    }

    private func record(_ text: String) {
        // 같은 텍스트가 이미 있으면 위로 끌어올리되 고정 상태는 유지
        let wasPinned = entries.first { $0.text == text && !$0.isImage }?.pinned ?? false
        entries.removeAll { $0.text == text && !$0.isImage }
        entries.insert(Entry(text: text, date: Date(), pinned: wasPinned), at: 0)
        trim()
        store.scheduleSave(entries)
    }

    private func recordImage(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              png.count <= maxImageBytes else { return }

        let file = "\(Int(Date().timeIntervalSince1970 * 1000)).png"
        do {
            try png.write(to: imagesDir.appendingPathComponent(file))
        } catch { return }

        let label = "이미지 \(rep.pixelsWide)×\(rep.pixelsHigh)"
        entries.insert(Entry(text: label, date: Date(), imageFile: file), at: 0)
        trim()
        store.scheduleSave(entries)
    }

    /// 항목을 최신으로 끌어올림 (이미지 복사 시 — 파일은 그대로 재사용)
    private func touch(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.imageFile == entry.imageFile && $0.imageFile != nil }) else { return }
        var updated = entries.remove(at: index)
        updated = Entry(text: updated.text, date: Date(), pinned: updated.pinned, imageFile: updated.imageFile)
        entries.insert(updated, at: 0)
        store.scheduleSave(entries)
    }

    /// 고정 안 된 항목만 maxEntries로 제한, 밀려난 이미지는 파일도 삭제
    private func trim() {
        var unpinnedCount = 0
        var removed: [Entry] = []
        entries.removeAll { entry in
            guard !entry.pinned else { return false }
            unpinnedCount += 1
            if unpinnedCount > maxEntries {
                removed.append(entry)
                return true
            }
            return false
        }
        for entry in removed {
            if let file = entry.imageFile {
                try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(file))
                thumbnailCache[file] = nil
            }
        }
    }
}
