import Foundation
import Security

/// 앱과 위젯이 함께 쓰는 App Group.
enum AppGroup {
    /// 권한 파일의 `com.apple.security.application-groups` 첫 항목.
    /// 팀 ID가 앞에 붙는 이름이라 코드에 적어 두지 않고 서명에서 읽는다.
    static let identifier: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil),
              let groups = value as? [String] else { return nil }
        return groups.first
    }()

    static let containerURL: URL? = {
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }()
}

/// 위젯 종류 이름. 앱이 위젯을 새로 고칠 때도 쓴다.
enum WidgetKind {
    static let nowPlaying = "NowPlayingWidget"
}

/// 위젯을 눌렀을 때 앱(Spot)으로 넘어오는 주소.
enum DeepLink {
    static let scheme = "spot"
    static let host = "now-playing"
    static let openMusic = URL(string: "spot://now-playing")!
}
