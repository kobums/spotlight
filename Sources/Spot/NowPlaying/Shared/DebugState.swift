#if DEBUG
import Foundation
import notify

/// Debug 빌드 전용: 음악을 틀지 않고 위젯 화면을 확인하는 길. `tools/debug_state.sh`가 쓴다.
///
/// App Group 폴더에 `debug-state.json`이 있으면 위젯이 실제 상태 대신 그 내용을 보여 준다.
/// 파일을 바꾼 뒤 Darwin 알림을 보내면 앱이 위젯을 새로 고친다. Release 빌드에는 들어가지 않는다.
enum DebugState {
    static let fileName = "debug-state.json"
    static let reloadNotification = "com.gowoobro.spot.nowplaying.debug.reload"

    static func load() -> NowPlayingSnapshot? {
        guard let url = SharedStore.fileURL(fileName), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
    }

    static func observeReload(_ handler: @escaping @Sendable () -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(reloadNotification, &token, .main) { _ in handler() }
    }
}
#endif
