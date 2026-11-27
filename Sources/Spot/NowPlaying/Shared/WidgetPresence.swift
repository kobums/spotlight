import Foundation
import notify

/// 위젯이 그려질 때 앱에 "위젯이 놓여 있다"고 알리는 신호 (Darwin 알림).
///
/// 앱은 위젯이 놓여 있을 때만 재생 상태를 따라간다. 앱이 켜진 뒤에 위젯을 추가해도
/// 바로 시작할 수 있게, 위젯이 타임라인을 만들 때마다 이 신호를 보낸다.
enum WidgetPresence {
    private static let notificationName = "com.gowoobro.spot.nowplaying.widget.present"

    /// 위젯 쪽: 그려질 때 부른다.
    static func announce() {
        notify_post(notificationName)
    }

    /// 앱 쪽: 신호가 오면 메인 큐에서 `handler`를 부른다.
    static func observe(_ handler: @escaping @Sendable () -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(notificationName, &token, .main) { _ in handler() }
    }
}
