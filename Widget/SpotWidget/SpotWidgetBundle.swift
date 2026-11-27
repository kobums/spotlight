import SwiftUI
import WidgetKit

/// Spot의 위젯 확장. 위젯을 더 만들면 여기에 나열한다.
@main
struct SpotWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
    }
}
