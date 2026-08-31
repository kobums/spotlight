import AppKit

/// 메뉴바 메뉴 상단의 모니터별 밝기·볼륨 슬라이더 (MonitorControl 스타일).
///
/// NSMenuItem.view에 카드 뷰를 얹는 방식 — MonitorControl의 메뉴 구성과 동일.
/// 메뉴가 열릴 때마다 최신 모니터 목록·값으로 다시 그린다.
final class DisplayMenuSection {
    private var items: [NSMenuItem] = []

    func refresh(menu: NSMenu) {
        for item in items { menu.removeItem(item) }
        items = []

        let monitors = DisplayControlManager.shared.monitors
        guard !monitors.isEmpty else { return }

        var insertAt = 0
        for (index, monitor) in monitors.enumerated() {
            let item = NSMenuItem()
            item.view = MonitorCardView(monitor: monitor, index: index)
            menu.insertItem(item, at: insertAt)
            items.append(item)
            insertAt += 1
        }
        let separator = NSMenuItem.separator()
        menu.insertItem(separator, at: insertAt)
        items.append(separator)
    }
}

/// 모니터 하나의 카드: 이름 + 밝기 슬라이더 + (지원 시) 볼륨 슬라이더
private final class MonitorCardView: NSView {
    private let index: Int
    private var brightnessWork: DispatchWorkItem?
    private var volumeWork: DispatchWorkItem?

    init(monitor: DisplayControlManager.Monitor, index: Int) {
        self.index = index
        let hasVolume = monitor.volume != nil
        let height: CGFloat = hasVolume ? 96 : 66
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: height))

        let name = NSTextField(labelWithString: monitor.name)
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = .secondaryLabelColor

        var rows: [NSView] = [name]
        // DDC는 0 밑 결합 디밍(감마) 구간까지 한 슬라이더로 — 표시 값과 실제 화면
        // 밝기가 어긋나지 않게. 감마 전용은 완전히 검어지면 조작 불능이라 하한 반영.
        rows.append(sliderRow(symbol: "sun.max.fill",
                              value: monitor.combinedBrightness,
                              minValue: monitor.isDDC ? GammaDimmer.minPercent - 100 : GammaDimmer.minPercent,
                              action: #selector(brightnessChanged)))
        if hasVolume {
            rows.append(sliderRow(symbol: "speaker.wave.2.fill",
                                  value: monitor.muted ? 0 : (monitor.volume ?? 0),
                                  minValue: 0,
                                  action: #selector(volumeChanged)))
        }

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func sliderRow(symbol: String, value: Int, minValue: Int, action: Selector) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let slider = NSSlider(value: Double(value), minValue: Double(minValue), maxValue: 100,
                              target: self, action: action)
        slider.isContinuous = true

        let row = NSStackView(views: [icon, slider])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 252).isActive = true
        return row
    }

    // 드래그 중엔 20Hz로 코얼레싱하고 마우스를 놓으면 즉시 반영 —
    // DDC 쓰기(수십 ms)가 큐에 쌓여 슬라이더보다 한참 뒤처지는 것을 막는다
    private func coalesce(_ work: inout DispatchWorkItem?, _ action: @escaping () -> Void) {
        work?.cancel()
        if let event = NSApp.currentEvent, event.type == .leftMouseUp {
            action()
            return
        }
        let item = DispatchWorkItem(block: action)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    @objc private func brightnessChanged(_ slider: NSSlider) {
        let value = Int(slider.doubleValue.rounded())
        coalesce(&brightnessWork) { [index] in
            DisplayControlManager.shared.setBrightness(at: index, to: value)
        }
    }

    @objc private func volumeChanged(_ slider: NSSlider) {
        let value = Int(slider.doubleValue.rounded())
        coalesce(&volumeWork) { [index] in
            DisplayControlManager.shared.setVolume(at: index, to: value)
        }
    }
}
