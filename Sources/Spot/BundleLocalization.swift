import Foundation

/// 번들의 현지화된 표시 이름 읽기 — AppProvider(앱)와 SystemSettingsProvider(설정 패널) 공용.
///
/// FileManager.displayName은 호출 앱(Spot)이 해당 언어를 선언하지 않으면 영어 이름만
/// 돌려주므로, 대상 번들의 InfoPlist.loctable(신형식)·<lang>.lproj/InfoPlist.strings(구형식)를
/// 직접 읽는다.
enum BundleLocalization {
    /// 사용자 선호 언어의 주 언어 코드 목록, 예: ["ko", "en"]
    static let preferredLangCodes: [String] = {
        var seen = Set<String>()
        return Locale.preferredLanguages.compactMap { tag in
            let code = String(tag.prefix(while: { $0 != "-" && $0 != "_" }))
            return seen.insert(code).inserted ? code : nil
        }
    }()

    /// 번들의 현지화된 표시 이름들. loctable 우선, 없으면 lproj strings.
    static func localizedNames(bundleURL: URL) -> [String] {
        let resources = bundleURL.appendingPathComponent("Contents/Resources")
        let nameKeys = ["CFBundleDisplayName", "CFBundleName"]
        var names: [String] = []

        if let table = NSDictionary(contentsOf: resources.appendingPathComponent("InfoPlist.loctable"))
            as? [String: [String: Any]] {
            for lang in preferredLangCodes {
                guard let entry = table[lang] else { continue }
                names += nameKeys.compactMap { entry[$0] as? String }
                if !names.isEmpty { break }
            }
        }
        if names.isEmpty {
            for lang in preferredLangCodes {
                let strings = resources.appendingPathComponent("\(lang).lproj/InfoPlist.strings")
                guard let dict = NSDictionary(contentsOf: strings) as? [String: String] else { continue }
                names += nameKeys.compactMap { dict[$0] }
                if !names.isEmpty { break }
            }
        }
        return names
    }
}
