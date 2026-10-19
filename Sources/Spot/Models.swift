import AppKit

enum ResultKind {
    case app
    case file
    case calculator
    case clipboard
    case systemAction
    case settingsPane
    case webSearch
    case uiElement
    case menuItem
    case emoji
    case bookmark
    case snippet
    case browserTab
    case runningApp   // 프로세스 종료 명령의 대상 앱
    case window       // 창 전환기의 열린 창
}

struct SearchResult: Identifiable {
    let id: String            // frecency 키로도 사용 (예: "app:/Applications/Safari.app")
    let kind: ResultKind
    let title: String
    let subtitle: String
    let icon: NSImage?
    let symbolName: String?   // icon이 없을 때 SF Symbol 사용
    var score: Double
    let action: (NSEvent.ModifierFlags) -> Void

    init(
        id: String,
        kind: ResultKind,
        title: String,
        subtitle: String = "",
        icon: NSImage? = nil,
        symbolName: String? = nil,
        score: Double,
        action: @escaping (NSEvent.ModifierFlags) -> Void
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.symbolName = symbolName
        self.score = score
        self.action = action
    }
}
