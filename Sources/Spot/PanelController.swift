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

    private let panelWidth: CGFloat = 680
    private let fieldHeight: CGFloat = 60
    private let rowHeight: CGFloat = 48
    private let footerHeight: CGFloat = 26
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

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        viewModel.reset()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        focusSearchField()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - panelWidth / 2
        let y = frame.minY + frame.height * 0.68
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    private func resize(resultCount: Int) {
        let rows = min(resultCount, maxVisibleRows)
        let listHeight = rows > 0 ? CGFloat(rows) * rowHeight + footerHeight + 8 : 0
        let newHeight = fieldHeight + listHeight
        var frame = panel.frame
        let topY = frame.maxY
        frame.size.height = newHeight
        frame.origin.y = topY - newHeight
        panel.setFrame(frame, display: true, animate: false)
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
