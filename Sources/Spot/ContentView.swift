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
