import AppKit
import SwiftUI

/// 밝기·볼륨 조절 시 화면에 잠깐 뜨는 표시기.
///
/// macOS 기본 HUD는 시스템이 제어할 수 있는 장치에만 뜬다. 외장 모니터를 감마나
/// DDC로 우리가 직접 조절할 때는 아무 피드백이 없어서 직접 그린다.
/// 키를 받지 않는 순수 표시용 오버레이 — 키 윈도우가 되지 않고 클릭도 통과한다.
final class DisplayHUD {
    private static let size = NSSize(width: 200, height: 200)
    private static let duration = 1.2

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ feedback: DisplayControlManager.Feedback) {
        let screen = Self.screen(for: feedback.displayID) ?? NSScreen.main
        guard let screen else { return }

        // 조절 대상 화면 하단 중앙 — macOS 기본 HUD와 같은 자리
        let origin = NSPoint(
            x: screen.frame.midX - Self.size.width / 2,
            y: screen.frame.minY + 140)
        let frame = NSRect(origin: origin, size: Self.size)

        let panel = self.panel ?? makePanel(frame: frame)
        panel.contentView = NSHostingView(rootView: HUDView(feedback: feedback))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    private static func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }
    }
}

private struct HUDView: View {
    let feedback: DisplayControlManager.Feedback

    /// macOS HUD와 같은 16칸 눈금
    private static let segments = 16

    private var symbol: String {
        switch feedback.kind {
        case .brightness: return "sun.max.fill"
        case .volume: return feedback.muted || feedback.value == 0
            ? "speaker.slash.fill" : "speaker.wave.3.fill"
        }
    }

    /// 음소거 상태에서는 눈금을 비워 보여준다
    private var filled: Int {
        let value = feedback.muted ? 0 : feedback.value
        return Int((Double(value) / 100 * Double(Self.segments)).rounded())
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 62, weight: .regular))
                .foregroundStyle(.primary)
            HStack(spacing: 3) {
                ForEach(0..<Self.segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(index < filled ? Color.primary : Color.primary.opacity(0.22))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}
