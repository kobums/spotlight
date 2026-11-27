import Foundation

/// App Group 폴더에 두는 상태 파일. 앱이 쓰고 위젯이 읽는다.
enum SharedStore {
    private static let snapshotFileName = "now-playing.json"

    static var directory: URL? {
        AppGroup.containerURL?.appendingPathComponent("NowPlaying", isDirectory: true)
    }

    static func fileURL(_ name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return directory?.appendingPathComponent(name)
    }

    static func load() -> NowPlayingSnapshot? {
        guard let url = fileURL(snapshotFileName), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
    }

    static func save(_ snapshot: NowPlayingSnapshot) throws {
        guard let directory, let url = fileURL(snapshotFileName) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    static func writeFile(_ data: Data, name: String) throws {
        guard let directory, let url = fileURL(name) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// 이름이 `prefix`로 시작하는 파일 가운데 `keep`에 없는 것을 지운다.
    static func removeFiles(withPrefix prefix: String, keeping keep: Set<String>) {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix) && !keep.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
