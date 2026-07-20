import AppKit
import Carbon.HIToolbox

/// 전역 단축키 조합. Carbon 마스크로 저장한다 (RegisterEventHotKey에 그대로 전달).
struct KeyCombo: Codable, Equatable {
    var keyCode: Int
    var carbonModifiers: Int

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        return carbon
    }

    var display: String {
        var text = ""
        if carbonModifiers & controlKey != 0 { text += "⌃" }
        if carbonModifiers & optionKey != 0 { text += "⌥" }
        if carbonModifiers & shiftKey != 0 { text += "⇧" }
        if carbonModifiers & cmdKey != 0 { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    static func keyName(for keyCode: Int) -> String {
        if let name = keyNames[keyCode] { return name }
        return "key\(keyCode)"
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
    ]
}

/// 창 배치 설정 — 설정 창에서 편집하고 JSON으로 영속된다.
struct WindowSettings: Codable {
    /// 창 사이 간격(px). 화면 가장자리는 gap, 창끼리 맞닿는 안쪽 변은 gap/2씩.
    var gap: Double = 0
    /// 절반 액션 반복 시 순환하는 분율 (순환 순서대로)
    var cycleFractions: [Double] = [1 / 2.0, 2 / 3.0, 1 / 3.0]
    /// WindowAction.rawValue → 단축키. 없으면 해당 액션은 전역 단축키 미등록.
    var shortcuts: [String: KeyCombo] = WindowSettings.defaultShortcuts

    /// 순환 분율 후보 (설정 UI 표시·순환 순서)
    static let fractionCandidates: [Double] = [1 / 2.0, 2 / 3.0, 3 / 4.0, 1 / 4.0, 1 / 3.0]
    static let fractionLabels: [String] = ["½", "⅔", "¾", "¼", "⅓"]

    /// 사용자가 Rectangle에서 쓰던 기본 단축키
    static let defaultShortcuts: [String: KeyCombo] = [
        WindowAction.leftHalf.rawValue: KeyCombo(keyCode: kVK_LeftArrow, carbonModifiers: optionKey | cmdKey),
        WindowAction.rightHalf.rawValue: KeyCombo(keyCode: kVK_RightArrow, carbonModifiers: optionKey | cmdKey),
        WindowAction.topHalf.rawValue: KeyCombo(keyCode: kVK_UpArrow, carbonModifiers: optionKey | cmdKey),
        WindowAction.bottomHalf.rawValue: KeyCombo(keyCode: kVK_DownArrow, carbonModifiers: optionKey | cmdKey),
        WindowAction.topLeft.rawValue: KeyCombo(keyCode: kVK_LeftArrow, carbonModifiers: controlKey | cmdKey),
        WindowAction.topRight.rawValue: KeyCombo(keyCode: kVK_RightArrow, carbonModifiers: controlKey | cmdKey),
        WindowAction.bottomLeft.rawValue: KeyCombo(keyCode: kVK_LeftArrow, carbonModifiers: controlKey | shiftKey | cmdKey),
        WindowAction.bottomRight.rawValue: KeyCombo(keyCode: kVK_RightArrow, carbonModifiers: controlKey | shiftKey | cmdKey),
        WindowAction.maximize.rawValue: KeyCombo(keyCode: kVK_ANSI_F, carbonModifiers: optionKey | cmdKey),
        WindowAction.maximizeHeight.rawValue: KeyCombo(keyCode: kVK_UpArrow, carbonModifiers: controlKey | optionKey | shiftKey),
        WindowAction.smaller.rawValue: KeyCombo(keyCode: kVK_LeftArrow, carbonModifiers: controlKey | optionKey | shiftKey),
        WindowAction.larger.rawValue: KeyCombo(keyCode: kVK_RightArrow, carbonModifiers: controlKey | optionKey | shiftKey),
        WindowAction.center.rawValue: KeyCombo(keyCode: kVK_ANSI_C, carbonModifiers: optionKey | cmdKey),
        WindowAction.restore.rawValue: KeyCombo(keyCode: kVK_Delete, carbonModifiers: controlKey | optionKey),
        WindowAction.nextDisplay.rawValue: KeyCombo(keyCode: kVK_RightArrow, carbonModifiers: optionKey | shiftKey | cmdKey),
        WindowAction.previousDisplay.rawValue: KeyCombo(keyCode: kVK_LeftArrow, carbonModifiers: optionKey | shiftKey | cmdKey),
    ]
}

/// 설정 단일 저장소. 변경 시 저장을 예약하고 onChange(핫키 재등록)를 부른다.
final class WindowSettingsStore {
    static let shared = WindowSettingsStore()

    var onChange: (() -> Void)?
    private let store = JSONFileStore<WindowSettings>(filename: "window-settings.json", saveDelay: 0.5)
    private(set) var settings: WindowSettings

    private init() {
        settings = store.load() ?? WindowSettings()
    }

    func update(_ mutate: (inout WindowSettings) -> Void) {
        mutate(&settings)
        if settings.cycleFractions.isEmpty { settings.cycleFractions = [1 / 2.0] }
        store.scheduleSave(settings)
        onChange?()
    }
}
