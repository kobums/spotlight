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
