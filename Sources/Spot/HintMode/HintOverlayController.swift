import AppKit
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

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case 53: // Esc
            cancel()
            return nil
        case 51: // Delete
            if !model.typed.isEmpty { model.typed.removeLast() }
            return nil
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              characters.count == 1, characters.first!.isLetter else {
            return nil
        }

        let candidate = model.typed + characters
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
