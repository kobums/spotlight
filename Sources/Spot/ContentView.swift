import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SearchViewModel
    @Namespace private var selectionNamespace
    @State private var hoveredIndex: Int?

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.secondary)
                SearchField(
                    text: $viewModel.query,
                    onChange: { viewModel.queryChanged($0) },
                    onMove: { viewModel.moveSelection(by: $0) },
                    onSubmit: { viewModel.executeSelected(modifiers: $0) },
                    onCancel: { viewModel.cancel() }
                )
            }
            .padding(.horizontal, 22)
            .frame(height: 60)

            if !viewModel.results.isEmpty {
                resultsList
            }
        }
        .modifier(PanelChrome())
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(
                            result: result,
                            isSelected: index == viewModel.selectedIndex,
                            isHovered: index == hoveredIndex,
                            namespace: selectionNamespace
                        ) {
                            viewModel.selectedIndex = index
                            viewModel.executeSelected(modifiers: [])
                        }
                        .id(result.id)
                        .onHover { hovering in
                            hoveredIndex = hovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
                        }
                    }
                }
                .padding(6)
            }
            // 선택 이동은 즉답(스크롤은 애니메이션 없이), 하이라이트만 부드럽게 따라감
            .onChange(of: viewModel.selectedIndex) { newIndex in
                if viewModel.results.indices.contains(newIndex) {
                    proxy.scrollTo(viewModel.results[newIndex].id, anchor: nil)
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1.0),
                value: viewModel.selectedIndex
            )
        }
    }

}

struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let isHovered: Bool
    let namespace: Namespace.ID
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 11) {
            iconView
                .frame(width: 26, height: 26)

            Text(result.title)
                .font(titleFont)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 12)

            // 시스템 Spotlight처럼 부가 정보는 오른쪽 정렬
            if !result.subtitle.isEmpty {
                Text(result.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background {
            if isSelected {
                // 선택 하이라이트가 행 사이를 미끄러지듯 이동
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .matchedGeometryEffect(id: "selection", in: namespace)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        // 프레스 즉시 피드백(pointer-down), 커밋은 릴리즈에
        .onLongPressGesture(
            minimumDuration: .infinity,
            pressing: { pressing in isPressed = pressing },
            perform: {}
        )
        .simultaneousGesture(TapGesture().onEnded { onTap() })
    }

    private var titleFont: Font {
        if result.kind == .calculator {
            return .system(size: 15, weight: .semibold).monospacedDigit()
        }
        return .system(size: 14, weight: .medium)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = result.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else if let symbol = result.symbolName {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
        } else {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }
}

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
