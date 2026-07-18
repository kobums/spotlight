import SwiftUI

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
        .background { selectionBackground }
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

    @ViewBuilder
    private var selectionBackground: some View {
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
