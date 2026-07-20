import Foundation

/// 모니터 밝기·볼륨 제어 명령 (MonitorControl 대체):
/// "밝기", "밝기 50", "밝기 +10", "밝기 lg 30", "볼륨 30", "음소거".
final class DisplayProvider: SearchProvider {
    private enum Command {
        case brightness, volume, mute
    }

    private static let keywords: [(words: [String], command: Command)] = [
        (["밝기", "brightness"], .brightness),
        (["볼륨", "volume", "모니터볼륨"], .volume),
        (["음소거", "mute"], .mute),
    ]

    func results(for query: String) -> [SearchResult] {
        let parts = query.split(separator: " ").map(String.init)
        guard let first = parts.first else { return [] }

        var bestScore: Double?
        var command: Command?
        for (words, cmd) in Self.keywords {
            let scores = words.compactMap { FuzzyMatch.score(needle: first, haystack: $0) }
            if let s = scores.max(), s > (bestScore ?? -.infinity) {
                bestScore = s
                command = cmd
            }
        }
        guard let bestScore, let command else { return [] }
        let baseScore = (bestScore.isInfinite ? Score.actionExact : bestScore) + Score.actionBonus

        // 인자 파싱: 숫자(±상대 포함)는 값, 나머지는 모니터 이름 토큰
        var value: Int?
        var relative = false
        var target: String?
        for token in parts.dropFirst() {
            if let parsed = Self.parseValue(token) {
                value = parsed.value
                relative = parsed.relative
            } else if target == nil {
                target = token
            } else {
                return [] // 해석 안 되는 토큰이 있으면 담당 아님
            }
        }

        let manager = DisplayControlManager.shared
        let indices = manager.matching(target)
        // 이름 토큰이 아무 모니터와도 안 맞으면 담당 아님 (파일 검색 등에 양보)
        if target != nil && indices.isEmpty { return [] }

        if manager.monitors.isEmpty {
            return [SearchResult(
                id: "display:none", kind: .systemAction,
                title: "제어 가능한 외장 모니터 없음",
                subtitle: "모니터를 연결하면 밝기·볼륨을 제어할 수 있습니다",
                symbolName: "display.trianglebadge.exclamationmark",
                score: baseScore, action: { _ in })]
        }

        switch command {
        case .brightness: return brightnessResults(value: value, relative: relative, target: target, indices: indices, score: baseScore)
        case .volume: return volumeResults(value: value, relative: relative, target: target, indices: indices, score: baseScore)
        case .mute: return muteResults(target: target, indices: indices, score: baseScore)
        }
    }

    // MARK: - 결과 구성

    private func brightnessResults(value: Int?, relative: Bool, target: String?,
                                   indices: [Int], score: Double) -> [SearchResult] {
        let manager = DisplayControlManager.shared
        guard let value else {
            // 값 없음 → 현재 상태 표시
            return indices.map { index in
                let monitor = manager.monitors[index]
                return SearchResult(
                    id: "display:brightness:info:\(monitor.name)", kind: .systemAction,
                    title: "\(monitor.name) — 밝기 \(monitor.brightness)%",
                    subtitle: "\(monitor.methodLabel) · \"밝기 50\" 또는 \"밝기 +10\"으로 조절",
                    symbolName: "sun.max", score: score, action: { _ in })
            }
        }
        let valueText = relative ? (value >= 0 ? "+\(value)" : "\(value)") : "\(value)%"
        let names = indices.map { manager.monitors[$0].name }.joined(separator: ", ")
        return [SearchResult(
            id: "display:brightness:set", kind: .systemAction,
            title: "밝기 \(valueText)\(relative ? "" : "로 설정")",
            subtitle: names,
            symbolName: "sun.max.fill", score: score + 2,
            action: { _ in DisplayControlManager.shared.setBrightness(value, target: target, relative: relative) })]
    }

    private func volumeResults(value: Int?, relative: Bool, target: String?,
                               indices: [Int], score: Double) -> [SearchResult] {
        let manager = DisplayControlManager.shared
        let capable = indices.filter { manager.monitors[$0].volume != nil }
        guard !capable.isEmpty else {
            return [SearchResult(
                id: "display:volume:none", kind: .systemAction,
                title: "볼륨 제어 가능한 모니터 없음",
                subtitle: "DDC 하드웨어 제어가 되는 모니터만 지원됩니다",
                symbolName: "speaker.slash", score: score, action: { _ in })]
        }
        guard let value else {
            return capable.map { index in
                let monitor = manager.monitors[index]
                let volumeText = monitor.muted ? "음소거됨" : "볼륨 \(monitor.volume ?? 0)%"
                return SearchResult(
                    id: "display:volume:info:\(monitor.name)", kind: .systemAction,
                    title: "\(monitor.name) — \(volumeText)",
                    subtitle: "\"볼륨 30\" 또는 \"볼륨 +5\"로 조절",
                    symbolName: "speaker.wave.2", score: score, action: { _ in })
            }
        }
        let valueText = relative ? (value >= 0 ? "+\(value)" : "\(value)") : "\(value)%"
        let names = capable.map { manager.monitors[$0].name }.joined(separator: ", ")
        return [SearchResult(
            id: "display:volume:set", kind: .systemAction,
            title: "모니터 볼륨 \(valueText)\(relative ? "" : "로 설정")",
            subtitle: names,
            symbolName: "speaker.wave.2.fill", score: score + 2,
            action: { _ in DisplayControlManager.shared.setVolume(value, target: target, relative: relative) })]
    }

    private func muteResults(target: String?, indices: [Int], score: Double) -> [SearchResult] {
        let manager = DisplayControlManager.shared
        let capable = indices.filter { manager.monitors[$0].isDDC }
        guard !capable.isEmpty else { return [] }
        let anyMuted = capable.contains { manager.monitors[$0].muted }
        let names = capable.map { manager.monitors[$0].name }.joined(separator: ", ")
        return [SearchResult(
            id: "display:mute", kind: .systemAction,
            title: anyMuted ? "모니터 음소거 해제" : "모니터 음소거",
            subtitle: names,
            symbolName: anyMuted ? "speaker.slash.fill" : "speaker.slash",
            score: score,
            action: { _ in DisplayControlManager.shared.toggleMute(target: target) })]
    }

    /// "50" → 절대, "+10"/"-10" → 상대
    private static func parseValue(_ token: String) -> (value: Int, relative: Bool)? {
        if token.hasPrefix("+") || token.hasPrefix("-") {
            guard let n = Int(token) else { return nil }
            return (n, true)
        }
        guard let n = Int(token), (0...100).contains(n) else { return nil }
        return (n, false)
    }
}
