import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Spot 설정 창 (Rectangle 환경설정 대응). 메뉴바 → "설정…"으로 연다.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Spot 설정"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 뷰 모델

final class SettingsViewModel: ObservableObject {
    @Published private(set) var settings: WindowSettings = WindowSettingsStore.shared.settings
    /// 현재 단축키를 녹화 중인 액션
    @Published var recordingAction: WindowAction?
    private var keyMonitor: Any?

    func update(_ mutate: (inout WindowSettings) -> Void) {
        WindowSettingsStore.shared.update(mutate)
        settings = WindowSettingsStore.shared.settings
    }

    // MARK: 단축키 녹화

    func toggleRecording(_ action: WindowAction) {
        if recordingAction == action {
            stopRecording()
        } else {
            startRecording(action)
        }
    }

    private func startRecording(_ action: WindowAction) {
        stopRecording()
        recordingAction = action
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecording(event)
            return nil // 녹화 중 키는 삼킨다
        }
    }

    func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        recordingAction = nil
    }

    private func handleRecording(_ event: NSEvent) {
        guard let action = recordingAction else { return }
        if Int(event.keyCode) == kVK_Escape {
            stopRecording()
            return
        }
        let carbon = KeyCombo.carbonModifiers(from: event.modifierFlags)
        // 수식키 없는 단독 키나 ⇧ 단독은 전역 단축키로 부적합 — 무시
        guard carbon & ~shiftKey != 0 else { return }
        update { $0.shortcuts[action.rawValue] = KeyCombo(keyCode: Int(event.keyCode), carbonModifiers: carbon) }
        stopRecording()
    }

    func clearShortcut(_ action: WindowAction) {
        update { $0.shortcuts[action.rawValue] = nil }
    }

    func restoreDefaultShortcuts() {
        stopRecording()
        update { $0.shortcuts = WindowSettings.defaultShortcuts }
    }

    // MARK: 순환 분율

    func isFractionEnabled(_ fraction: Double) -> Bool {
        settings.cycleFractions.contains { abs($0 - fraction) < 0.001 }
    }

    func toggleFraction(_ fraction: Double) {
        update { settings in
            var enabled = WindowSettings.fractionCandidates.filter { candidate in
                settings.cycleFractions.contains { abs($0 - candidate) < 0.001 }
            }
            if let index = enabled.firstIndex(where: { abs($0 - fraction) < 0.001 }) {
                enabled.remove(at: index)
            } else {
                enabled.append(fraction)
            }
            // 후보 순서 유지, 전부 끄면 ½만 남긴다
            let ordered = WindowSettings.fractionCandidates.filter { candidate in
                enabled.contains { abs($0 - candidate) < 0.001 }
            }
            settings.cycleFractions = ordered.isEmpty ? [1 / 2.0] : ordered
        }
    }
}

// MARK: - 뷰

struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    @StateObject private var inputSourceModel = InputSourceSettingsViewModel()

    var body: some View {
        TabView {
            ShortcutsTab(model: model)
                .tabItem { Label("키보드 단축키", systemImage: "command") }
            GeneralTab(model: model)
                .tabItem { Label("설정", systemImage: "gearshape") }
            InputSourceTab(model: inputSourceModel)
                .tabItem { Label("입력 소스", systemImage: "keyboard") }
        }
        .frame(width: 560, height: 470)
        .onDisappear { model.stopRecording() }
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var model: SettingsViewModel

    private static let leftColumn: [WindowAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
    ]
    private static let rightColumn: [WindowAction] = [
        .maximize, .maximizeHeight, .smaller, .larger,
        .center, .restore, .nextDisplay, .previousDisplay,
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                column(Self.leftColumn)
                column(Self.rightColumn)
            }
            .padding(20)
            Spacer()
            HStack {
                Button("기본 단축키 복원") { model.restoreDefaultShortcuts() }
                Spacer()
                Text("단축키 칸을 누르고 새 조합을 입력하세요 (Esc 취소)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func column(_ actions: [WindowAction]) -> some View {
        VStack(spacing: 8) {
            ForEach(actions, id: \.self) { action in
                ShortcutRow(model: model, action: action)
            }
        }
    }
}

private struct ShortcutRow: View {
    @ObservedObject var model: SettingsViewModel
    let action: WindowAction

    var body: some View {
        let combo = model.settings.shortcuts[action.rawValue]
        let recording = model.recordingAction == action
        HStack(spacing: 6) {
            Text(action.displayName)
                .font(.system(size: 12))
                .frame(width: 96, alignment: .trailing)
            Button {
                model.toggleRecording(action)
            } label: {
                Text(recording ? "키를 누르세요…" : (combo?.display ?? "단축키 입력"))
                    .font(.system(size: 12, weight: combo == nil && !recording ? .regular : .medium))
                    .foregroundColor(recording ? .accentColor : (combo == nil ? .secondary : .primary))
                    .frame(width: 110)
            }
            Button {
                model.clearShortcut(action)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .opacity(combo == nil ? 0 : 1)
            .disabled(combo == nil)
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Text("커맨드 반복 입력 시 크기 순환")
                    ForEach(Array(WindowSettings.fractionCandidates.enumerated()), id: \.offset) { index, fraction in
                        Toggle(WindowSettings.fractionLabels[index], isOn: Binding(
                            get: { model.isFractionEnabled(fraction) },
                            set: { _ in model.toggleFraction(fraction) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.bottom, 8)

                HStack {
                    Text("창 사이 간격")
                    Slider(value: Binding(
                        get: { model.settings.gap },
                        set: { value in model.update { $0.gap = (value / 2).rounded() * 2 } }
                    ), in: 0...40)
                    Text("\(Int(model.settings.gap)) px")
                        .frame(width: 44, alignment: .trailing)
                        .monospacedDigit()
                }
            }

            Section {
                Text("설정은 ~/Library/Application Support/Spot/window-settings.json 에 저장됩니다.\n절반 액션(왼쪽/오른쪽/위쪽/아래쪽)을 같은 키로 반복하면 선택한 분율 순서대로 창 크기가 순환합니다.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 12)
            }

            Section {
                Text("Spot \(Self.version)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(20)
    }

    /// 앱 번들의 버전 (make-app.sh가 VERSION 파일 값을 Info.plist에 넣는다).
    /// swift run 개발 실행은 번들 정보가 없으므로 "dev"로 표시된다.
    private static let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
}
