import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 설정 창의 "입력 소스" 탭 — 앱별 규칙 관리 + 인디케이터 옵션.
final class InputSourceSettingsViewModel: ObservableObject {
    struct RuleRow: Identifiable {
        let bundleID: String
        let appName: String
        let icon: NSImage?
        let sourceID: String
        var id: String { bundleID }
    }

    @Published private(set) var rows: [RuleRow] = []
    @Published var indicatorEnabled: Bool
    @Published var indicatorDuration: Double
    let sources: [InputSourceManager.Source]

    init() {
        let manager = InputSourceManager.shared
        sources = manager.sources
        indicatorEnabled = manager.settings.indicatorEnabled
        indicatorDuration = manager.settings.indicatorDuration
        refresh()
        manager.onChange = { [weak self] in self?.refresh() }
    }

    func refresh() {
        let manager = InputSourceManager.shared
        rows = manager.rules.map { bundleID, sourceID in
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let name = appURL.map {
                BundleLocalization.localizedNames(bundleURL: $0).first
                    ?? (FileManager.default.displayName(atPath: $0.path) as NSString).deletingPathExtension
            } ?? bundleID
            let icon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            return RuleRow(bundleID: bundleID, appName: name, icon: icon, sourceID: sourceID)
        }
        .sorted { $0.appName.localizedCompare($1.appName) == .orderedAscending }
        indicatorEnabled = manager.settings.indicatorEnabled
        indicatorDuration = manager.settings.indicatorDuration
    }

    // MARK: - 규칙 편집

    func setSource(bundleID: String, sourceID: String) {
        InputSourceManager.shared.setRule(bundleID: bundleID, sourceID: sourceID)
    }

    func removeRule(bundleID: String) {
        InputSourceManager.shared.setRule(bundleID: bundleID, sourceID: nil)
    }

    /// 추가 시 현재 입력 소스로 등록 (드롭다운에서 바로 바꿀 수 있다)
    func addRule(bundleID: String) {
        let manager = InputSourceManager.shared
        guard manager.rule(for: bundleID) == nil else { return }
        let sourceID = manager.current?.id ?? sources.first?.id
        guard let sourceID else { return }
        manager.setRule(bundleID: bundleID, sourceID: sourceID)
    }

    /// 규칙이 아직 없는 실행 중인 일반 앱 목록
    var addableRunningApps: [(bundleID: String, name: String)] {
        let existing = Set(rows.map(\.bundleID))
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != Bundle.main.bundleIdentifier,
                      !existing.contains(bundleID),
                      seen.insert(bundleID).inserted else { return nil }
                return (bundleID, app.localizedName ?? bundleID)
            }
            .sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
    }

    func addViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.message = "입력 소스 규칙을 지정할 앱을 선택하세요"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        addRule(bundleID: bundleID)
    }
}

struct InputSourceTab: View {
    @ObservedObject var model: InputSourceSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("앱별 규칙 — 앱이 활성화되면 지정한 입력 소스로 자동 전환")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 2) {
                    if model.rows.isEmpty {
                        Text("등록된 규칙 없음 — 아래 \"앱 추가\" 또는 런처에서 \"입력규칙\"")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    ForEach(model.rows) { row in
                        HStack(spacing: 8) {
                            if let icon = row.icon {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            }
                            Text(row.appName).font(.system(size: 12))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { row.sourceID },
                                set: { model.setSource(bundleID: row.bundleID, sourceID: $0) }
                            )) {
                                ForEach(model.sources, id: \.id) { source in
                                    Text(source.name).tag(source.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                            Button {
                                model.removeRule(bundleID: row.bundleID)
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                    }
                }
            }
            .frame(maxHeight: 220)

            Menu("앱 추가") {
                ForEach(model.addableRunningApps, id: \.bundleID) { app in
                    Button(app.name) { model.addRule(bundleID: app.bundleID) }
                }
                Divider()
                Button("기타 앱 선택…") { model.addViaOpenPanel() }
            }
            .frame(width: 160)
            .padding(.top, 8)

            Divider().padding(.vertical, 14)

            Toggle("전환 시 한/A 배지 표시", isOn: Binding(
                get: { model.indicatorEnabled },
                set: { InputSourceManager.shared.setIndicator(enabled: $0) }
            ))
            HStack {
                Text("표시 시간")
                Slider(value: Binding(
                    get: { model.indicatorDuration },
                    set: { InputSourceManager.shared.setIndicator(duration: ($0 * 4).rounded() / 4) }
                ), in: 0.5...3)
                Text(String(format: "%.2g초", model.indicatorDuration))
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
            }
            .disabled(!model.indicatorEnabled)
            .padding(.top, 6)

            Spacer()
        }
        .padding(20)
        .onAppear { model.refresh() }
    }
}
