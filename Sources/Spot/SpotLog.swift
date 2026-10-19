import Foundation
import os

/// 앱 로그 — 통합 로그(Console.app, `log show --predicate 'subsystem == "com.gowoobro.spot"'`)와
/// 파일(`~/Library/Logs/Spot/spot.log`)에 같은 줄을 남긴다.
///
/// 전에는 아무것도 남기지 않아서, 다른 머신에서 "밝기가 안 된다"는 문제가 생겼을 때
/// 크래시 기록도 로그도 없이 릴리스 간 코드 diff로 원인을 추측해야 했다 (2026-10-19).
/// 파일은 사용자가 런처(`밝기 진단` → 로그 열기)에서 바로 열어 볼 수 있게 평문이다.
enum SpotLog {
    enum Category: String {
        case app, display, mediaKeys
    }

    static let fileURL: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/Spot", isDirectory: true)
        return logs.appendingPathComponent("spot.log")
    }()

    /// 이 크기를 넘으면 spot.log.1 로 한 번 돌린다 (이전 .1은 버린다)
    private static let maxBytes = 1_000_000

    private static let queue = DispatchQueue(label: "spot.log", qos: .utility)
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()

    static func info(_ message: String, _ category: Category = .app) {
        logger(category).info("\(message, privacy: .public)")
        append("INFO", category, message)
    }

    static func error(_ message: String, _ category: Category = .app) {
        logger(category).error("\(message, privacy: .public)")
        append("ERROR", category, message)
    }

    private static func logger(_ category: Category) -> Logger {
        Logger(subsystem: "com.gowoobro.spot", category: category.rawValue)
    }

    private static func append(_ level: String, _ category: Category, _ message: String) {
        let line = "\(formatter.string(from: Date())) \(level) [\(category.rawValue)] \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > maxBytes {
                let rotated = fileURL.appendingPathExtension("1")
                try? fm.removeItem(at: rotated)
                try? fm.moveItem(at: fileURL, to: rotated)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
