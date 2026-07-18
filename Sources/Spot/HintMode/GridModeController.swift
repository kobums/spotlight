import AppKit
import Carbon.HIToolbox
import SwiftUI

final class GridModel: ObservableObject {
    /// 오버레이 로컬 좌표(좌상단 원점)의 현재 선택 영역
    @Published var region: CGRect = .zero
}

/// 화면을 3×3 격자로 재귀 분할해 좌표를 좁혀가는 그리드 모드 (warpd/keynav 방식).
/// 접근성 트리가 없는 앱에서의 폴백 — QWE/ASD/ZXC로 칸 선택, Return/Space로 클릭.
final class GridModeController: NSObject, NSWindowDelegate {
    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private var panel: OverlayPanel?
    private var keyMonitor: Any?
    private var model = GridModel()
    private var screenOriginCG: CGPoint = .zero

    var isVisible: Bool { panel?.isVisible ?? false }

    /// keyCode → (열, 행). QWE 윗줄 / ASD 가운데 / ZXC 아랫줄 — 자판 배치가 곧 화면 배치
    private static let cells: [Int: (col: Int, row: Int)] = [
        kVK_ANSI_Q: (0, 0), kVK_ANSI_W: (1, 0), kVK_ANSI_E: (2, 0),
        kVK_ANSI_A: (0, 1), kVK_ANSI_S: (1, 1), kVK_ANSI_D: (2, 1),
        kVK_ANSI_Z: (0, 2), kVK_ANSI_X: (1, 2), kVK_ANSI_C: (2, 2),
    ]

    func show() {
        cancel()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        screenOriginCG = ScreenCoords.nsToCG(screen.frame).origin

        let model = GridModel()
        model.region = CGRect(origin: .zero, size: screen.frame.size)
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
        panel.contentView = NSHostingView(rootView: GridOverlayView(model: model))
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
        case kVK_Escape:
            cancel()
        case kVK_Return, kVK_Space:
            let point = regionCenterCG()
            cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                HintActionPerformer.click(at: point)
            }
        default:
            if let cell = Self.cells[Int(event.keyCode)] {
                narrow(to: cell)
            }
        }
        return nil // 그리드 모드 중에는 모든 키를 삼킨다
    }

    private func narrow(to cell: (col: Int, row: Int)) {
        let r = model.region
        let w = r.width / 3
        let h = r.height / 3
        model.region = CGRect(
            x: r.minX + CGFloat(cell.col) * w,
            y: r.minY + CGFloat(cell.row) * h,
            width: w,
            height: h
        )
        HintActionPerformer.moveCursor(to: regionCenterCG())
    }

    private func regionCenterCG() -> CGPoint {
        CGPoint(
            x: screenOriginCG.x + model.region.midX,
            y: screenOriginCG.y + model.region.midY
        )
    }
}

// MARK: - 그리기

private struct GridOverlayView: View {
    @ObservedObject var model: GridModel
    private static let labels = [["Q", "W", "E"], ["A", "S", "D"], ["Z", "X", "C"]]

    var body: some View {
        GeometryReader { geo in
            let r = model.region
            let w = r.width / 3
            let h = r.height / 3

            ZStack(alignment: .topLeading) {
                // 선택 영역 밖은 어둡게 (even-odd로 구멍)
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    p.addRect(r)
                }
                .fill(Color.black.opacity(0.3), style: FillStyle(eoFill: true))

                // 3×3 격자선
                Path { p in
                    for i in 1..<3 {
                        p.move(to: CGPoint(x: r.minX + CGFloat(i) * w, y: r.minY))
                        p.addLine(to: CGPoint(x: r.minX + CGFloat(i) * w, y: r.maxY))
                        p.move(to: CGPoint(x: r.minX, y: r.minY + CGFloat(i) * h))
                        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + CGFloat(i) * h))
                    }
                }
                .stroke(Color.yellow.opacity(0.7), lineWidth: 1)

                Path { p in p.addRect(r) }
                    .stroke(Color.yellow, lineWidth: 2)

                // 칸이 라벨을 담을 만큼 클 때만 표시
                if w > 30, h > 24 {
                    ForEach(0..<3, id: \.self) { row in
                        ForEach(0..<3, id: \.self) { col in
                            Text(Self.labels[row][col])
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color(red: 1.0, green: 0.87, blue: 0.4))
                                )
                                .position(
                                    x: r.minX + (CGFloat(col) + 0.5) * w,
                                    y: r.minY + (CGFloat(row) + 0.5) * h
                                )
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
