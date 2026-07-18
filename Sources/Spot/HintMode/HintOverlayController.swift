import AppKit
import Carbon.HIToolbox
import SwiftUI

struct Hint: Identifiable {
    let id: Int
    let label: String
    /// 오버레이 로컬 좌표(좌상단 원점), 요소 중심점
    let point: CGPoint
    let target: HintTarget
}

final class HintOverlayModel: ObservableObject {
    @Published var hints: [Hint] = []
    @Published var typed: String = ""
}

/// 화면 전체를 덮는 클릭 통과 패널에 힌트 라벨을 그리고, 키 입력으로 좁혀서 선택한다.
final class HintOverlayController: NSObject, NSWindowDelegate {
    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private var panel: OverlayPanel?
    private var model = HintOverlayModel()
    private var keyMonitor: Any?
    private var onSelect: ((HintTarget) -> Void)?

    /// Tab으로 스크롤 모드 전환
    var onSwitchToScrollMode: (() -> Void)?
    /// "/"로 그리드 모드 전환
    var onSwitchToGridMode: (() -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(targets: [HintTarget], on screen: NSScreen, onSelect: @escaping (HintTarget) -> Void) {
        cancel()
        self.onSelect = onSelect

        let screenCG = ScreenCoords.nsToCG(screen.frame)
        let labels = HintLabeler.labels(count: targets.count)
        let model = HintOverlayModel()
        model.hints = zip(targets, labels).enumerated().map { index, pair in
            let (target, label) = pair
            return Hint(
                id: index,
                label: label,
                point: CGPoint(x: target.frame.midX - screenCG.minX,
                               y: target.frame.midY - screenCG.minY),
                target: target
            )
        }
        self.model = model

        let panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HintOverlayView(model: model))
        panel.setFrame(screen.frame, display: true)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func cancel() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        onSelect = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        cancel()
    }

    // MARK: - 키 입력

    /// 물리 키 위치 → 라벨 문자. 한글 등 어떤 입력 소스가 켜져 있어도
    /// charactersIgnoringModifiers는 자모("ㅁ")를 돌려주므로 keyCode로 매핑한다.
    private static let letterForKeyCode: [Int: Character] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
    ]

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case kVK_Escape:
            cancel()
            return nil
        case kVK_Delete:
            if !model.typed.isEmpty { model.typed.removeLast() }
            return nil
        case kVK_Tab:
            onSwitchToScrollMode?()
            return nil
        case kVK_ANSI_Slash:
            onSwitchToGridMode?()
            return nil
        default:
            break
        }

        guard let letter = Self.letterForKeyCode[Int(event.keyCode)] else { return nil }

        let candidate = model.typed + String(letter)
        let matches = model.hints.filter { $0.label.hasPrefix(candidate) }
        if matches.count == 1, matches[0].label == candidate {
            let target = matches[0].target
            let callback = onSelect
            cancel()
            // 오버레이가 내려간 뒤 클릭이 실행되도록 살짝 지연
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                callback?(target)
            }
        } else if !matches.isEmpty {
            model.typed = candidate
        }
        return nil
    }
}

// MARK: - 그리기

struct HintOverlayView: View {
    @ObservedObject var model: HintOverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.hints) { hint in
                if hint.label.hasPrefix(model.typed) {
                    HintLabelView(label: hint.label, typedCount: model.typed.count)
                        .position(hint.point)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private struct HintLabelView: View {
    let label: String
    let typedCount: Int

    var body: some View {
        let typed = String(label.prefix(typedCount))
        let rest = String(label.dropFirst(typedCount))
        (Text(typed).foregroundColor(.black.opacity(0.3)) + Text(rest).foregroundColor(.black))
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.87, blue: 0.4))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
            )
    }
}
