import AppKit
import Combine
import SwiftUI

/// 포커스를 뺏지 않는 nonactivating NSPanel — Spotlight/Raycast 방식의 본질.
final class SpotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController: NSObject, NSWindowDelegate {
    private let panel: SpotPanel
    private let viewModel = SearchViewModel()

    private let panelWidth: CGFloat = 640
    private let fieldHeight: CGFloat = 60
    private let rowHeight: CGFloat = 42
    private let maxVisibleRows = 9

    private var cancellable: Any?

    override init() {
        panel = SpotPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 60),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        viewModel.onExecute = { [weak self] in self?.hide() }
        viewModel.onDismiss = { [weak self] in self?.hide() }

        let contentView = ContentView(viewModel: viewModel)
        panel.contentView = NSHostingView(rootView: contentView)

        // 결과 수에 따라 패널 높이 조정
        cancellable = viewModel.$results.sink { [weak self] results in
            DispatchQueue.main.async { self?.resize(resultCount: results.count) }
        }
    }

    private var isHiding = false

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func toggle() {
        if panel.isVisible && !isHiding {
            hide()
        } else {
            show()
        }
    }

    func show() {
        isHiding = false
        viewModel.reset()
        positionPanel()

        let targetFrame = panel.frame
        if reduceMotion {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        } else {
            // materialize: 살짝 위에서 내려앉으며 페이드 인
            var startFrame = targetFrame
            startFrame.origin.y += 8
            panel.setFrame(startFrame, display: false)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
                panel.animator().setFrame(targetFrame, display: true)
                panel.animator().alphaValue = 1
            }
        }
        focusSearchField()
    }

    func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.1 : 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.isHiding else { return }
            self.isHiding = false
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func positionPanel() {
        // 시스템 Spotlight처럼 마우스가 있는(활성) 화면에 표시
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - panelWidth / 2
        // 패널 상단이 화면 위에서 1/4 지점 (시스템 Spotlight 위치)
        let y = frame.minY + frame.height * 0.75
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    private func resize(resultCount: Int) {
        let rows = min(resultCount, maxVisibleRows)
        let listHeight = rows > 0 ? CGFloat(rows) * rowHeight + 12 : 0
        let newHeight = fieldHeight + listHeight
        var frame = panel.frame
        let topY = frame.maxY
        frame.size.height = newHeight
        frame.origin.y = topY - newHeight
        guard frame.size.height != panel.frame.size.height else { return }

        // 표시 전이거나 모션 감소 설정이면 즉시, 아니면 짧은 전환.
        // animator()는 매 호출 현재 프레임에서 재시작하므로 타이핑 중에도 끊기지 않는다.
        if !panel.isVisible || isHiding || reduceMotion {
            panel.setFrame(frame, display: true, animate: false)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let contentView = self.panel.contentView else { return }
            if let textField = Self.findTextField(in: contentView) {
                self.panel.makeFirstResponder(textField)
            }
        }
    }

    private static func findTextField(in view: NSView) -> NSTextField? {
        if let tf = view as? NSTextField { return tf }
        for subview in view.subviews {
            if let found = findTextField(in: subview) { return found }
        }
        return nil
    }
}
