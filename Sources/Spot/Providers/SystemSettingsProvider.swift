import AppKit

/// 시스템 설정 패널 검색 (Spotlight의 설정 검색 대응).
///
/// macOS 설정 패널은 /System/Library/ExtensionKit/Extensions의 확장 번들로,
/// EXExtensionPointIdentifier == "com.apple.Settings.extension.ui"가 실제 패널이다.
/// 한글 이름은 번들 loctable에서 읽고, 선택 시 x-apple.systempreferences: URL로 연다.
final class SystemSettingsProvider: SearchProvider {
    private struct Pane {
        let title: String
        let names: [String]
        let bundleID: String
    }

    private var panes: [Pane] = []
    private static let extensionsDir = "/System/Library/ExtensionKit/Extensions"

    /// loctable에 이름이 없거나(배터리) 한글 표기가 다른 패널 보강
    private static let aliases: [String: [String]] = [
        "com.apple.Battery-Settings.extension": ["배터리", "Battery", "전원"],
        "com.apple.BluetoothSettings": ["블루투스"],
        "com.apple.wifi-settings-extension": ["와이파이", "wifi"],
        "com.apple.HeadphoneSettings": ["헤드폰", "Headphones"],
        "com.apple.Displays-Settings.extension": ["모니터"],
    ]

    /// 설정 패널 공통 아이콘 (시스템 설정 앱 아이콘)
    private static let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/System Settings.app")

    init() {
        // 시스템 볼륨 내용은 OS 업데이트 전엔 안 바뀌므로 시작 시 1회만 스캔
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.scan()
            DispatchQueue.main.async { self?.panes = found }
        }
    }

    func results(for query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        var out: [SearchResult] = []
        for pane in panes {
            let scores = pane.names.compactMap { FuzzyMatch.score(needle: query, haystack: $0) }
            guard let best = scores.max() else { continue }
            let bundleID = pane.bundleID
            out.append(SearchResult(
                id: "settings:\(bundleID)",
                kind: .settingsPane,
                title: pane.title,
                subtitle: "시스템 설정",
                icon: Self.icon,
                score: best.isInfinite ? Score.settingsExact : best + Score.settingsBonus,
                action: { _ in
                    if let url = URL(string: "x-apple.systempreferences:\(bundleID)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            ))
        }
        return out
    }

    // MARK: - 스캔

    private static func scan() -> [Pane] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: extensionsDir) else { return [] }
        var found: [Pane] = []

        for item in items where item.hasSuffix(".appex") {
            let bundleURL = URL(fileURLWithPath: extensionsDir).appendingPathComponent(item)
            guard let info = NSDictionary(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist")),
                  let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                  (attributes["EXExtensionPointIdentifier"] as? String) == "com.apple.Settings.extension.ui",
                  let bundleID = info["CFBundleIdentifier"] as? String else { continue }

            let localized = BundleLocalization.localizedNames(bundleURL: bundleURL)
                .filter { !isJunkName($0) }
            let aliasNames = aliases[bundleID] ?? []
            // 표시할 만한 이름이 하나도 없으면 검색 노이즈만 되므로 제외
            guard let title = (localized + aliasNames).first else { continue }

            var seen = Set<String>()
            let names = (localized + aliasNames + [(info["CFBundleDisplayName"] as? String) ?? ""])
                .filter { !$0.isEmpty && !isJunkName($0) }
                .filter { seen.insert($0).inserted }
            found.append(Pane(title: title, names: names, bundleID: bundleID))
        }
        return found
    }

    /// "HeadphoneSettingsExtension"처럼 현지화가 안 된 내부 이름 걸러내기
    private static func isJunkName(_ name: String) -> Bool {
        name.hasSuffix("Extension") || name.hasSuffix("Ext") || name.hasSuffix(".extension")
    }
}
