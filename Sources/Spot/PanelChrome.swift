import SwiftUI

/// 패널 외형: macOS 26이면 Liquid Glass, 이전 버전은 blur, 투명도 감소 설정이면 불투명.
struct PanelChrome: ViewModifier {
    /// Tahoe Spotlight와 같은 큰 연속 코너
    static let cornerRadius: CGFloat = 30

    func body(content: Content) -> some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )
        } else if #available(macOS 26.0, *) {
            // Liquid Glass가 자체 림 라이트를 그리므로 별도 테두리 없음
            content
                .background(GlassBackgroundView(cornerRadius: Self.cornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        } else {
            content
                .background(VisualEffectView())
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.primary.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        }
    }
}

/// macOS 26 Liquid Glass 배경 — 시스템 Spotlight와 같은 재질
@available(macOS 26.0, *)
struct GlassBackgroundView: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
    }
}

/// 뒤 배경을 비치게 하는 blur 배경 (macOS 26 미만 폴백)
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
