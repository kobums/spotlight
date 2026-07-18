import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                SearchField(
                    text: $viewModel.query,
                    onChange: { viewModel.queryChanged($0) },
                    onMove: { viewModel.moveSelection(by: $0) },
                    onSubmit: { viewModel.executeSelected(modifiers: $0) },
                    onCancel: { viewModel.cancel() }
                )
            }
            .padding(.horizontal, 18)
            .frame(height: 60)

            if !viewModel.results.isEmpty {
                Divider()
                resultsList
                Divider()
                footer
            }
        }
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, isSelected: index == viewModel.selectedIndex)
                            .id(result.id)
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                viewModel.executeSelected(modifiers: [])
                            }
                    }
                }
                .padding(6)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                if viewModel.results.indices.contains(newIndex) {
                    proxy.scrollTo(viewModel.results[newIndex].id, anchor: nil)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint(key: "↑↓", label: "이동")
            hint(key: "⏎", label: "실행")
            hint(key: "⌥⏎", label: "Finder에서 보기")
            hint(key: "esc", label: "닫기")
            Spacer()
            Text("cb: 클립보드 · g/yt/gh/nv: 웹")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
    }

    private func hint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(result.kind.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(
            isSelected ? Color.accentColor.opacity(0.22) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
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

/// 뒤 배경을 비치게 하는 blur 배경
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
