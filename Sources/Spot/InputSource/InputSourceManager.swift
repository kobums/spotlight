import AppKit
import Carbon

/// 입력 소스 자동 전환 (Input Source Pro 대체).
///
/// 앱별 규칙(bundleID → 입력 소스 ID)을 저장해 두고, 앱이 활성화되면 적용한다.
/// 전환·변경 시 인디케이터로 현재 입력기를 표시한다. 전부 공개 API — 권한 불필요
/// (인디케이터의 캐럿 위치만 손쉬운 사용을 쓰며, 없으면 포인터 폴백).
final class InputSourceManager {
    static let shared = InputSourceManager()

    struct Source {
        let id: String
        let name: String
        /// 인디케이터 배지 글자: 한글 입력기는 "한", 그 외 "A"
        var badge: String { id.contains("Korean") ? "한" : "A" }
    }

    struct Settings: Codable {
        var rules: [String: String] = [:]  // bundleID → sourceID
        var indicatorEnabled: Bool = true
        var indicatorDuration: Double = 1.0
    }

    private let store = JSONFileStore<Settings>(filename: "input-rules.json", saveDelay: 0.5)
    private(set) var settings: Settings
    /// 설정 변경 알림 (설정 창 갱신용)
    var onChange: (() -> Void)?

    var rules: [String: String] { settings.rules }

    private let indicator = InputSourceIndicator()
    private var applyWork: DispatchWorkItem?
    /// 자동 전환 직후의 변경 알림에 인디케이터를 중복 표시하지 않기 위한 플래그
    private var suppressChangeIndicatorUntil = Date.distantPast

    private init() {
        // 구식 포맷([bundleID: sourceID] 딕셔너리) 마이그레이션 — 신형은 rules 값이
        // 객체라 [String: String] 디코드가 실패하는 것으로 포맷을 판별한다
        let legacyStore = JSONFileStore<[String: String]>(filename: "input-rules.json", saveDelay: 0.5)
        if let legacy = legacyStore.load() {
            settings = Settings(rules: legacy)
            store.scheduleSave(settings)
        } else {
            settings = store.load() ?? Settings()
        }
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(sourceDidChange),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil)
    }

    // MARK: - 소스 조회/전환

    /// 선택 가능한 키보드 입력 소스 목록
    var sources: [Source] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
            as? [TISInputSource] else { return [] }
        return list.compactMap { source in
            guard property(source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String),
                  boolProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  let id = property(source, kTISPropertyInputSourceID) else { return nil }
            return Source(id: id, name: property(source, kTISPropertyLocalizedName) ?? id)
        }
    }

    var current: Source? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let id = property(source, kTISPropertyInputSourceID) else { return nil }
        return Source(id: id, name: property(source, kTISPropertyLocalizedName) ?? id)
    }

    @discardableResult
    func select(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue()
            as? [TISInputSource], let source = list.first else { return false }
        return TISSelectInputSource(source) == noErr
    }

    // MARK: - 규칙

    func rule(for bundleID: String) -> String? {
        rules[bundleID]
    }

    func setRule(bundleID: String, sourceID: String?) {
        settings.rules[bundleID] = sourceID
        store.scheduleSave(settings)
        onChange?()
    }

    func setIndicator(enabled: Bool? = nil, duration: Double? = nil) {
        if let enabled { settings.indicatorEnabled = enabled }
        if let duration { settings.indicatorDuration = max(0.5, min(3.0, duration)) }
        store.scheduleSave(settings)
        onChange?()
    }

    /// 소스 ID → 표시 이름 (규칙 목록용)
    func sourceName(for id: String) -> String {
        sources.first { $0.id == id }?.name ?? id
    }

    // MARK: - 자동 적용

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              let targetID = rules[bundleID] else { return }

        applyWork?.cancel()
        // 앱이 포커스를 완전히 잡기 전에 전환하면 씹힐 수 있어 잠시 후 적용
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.current?.id != targetID else { return }
            self.suppressChangeIndicatorUntil = Date().addingTimeInterval(0.5)
            self.select(id: targetID)
            // 적용 검증 — 실패했으면 1회 재시도
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if self.current?.id != targetID { self.select(id: targetID) }
                self.showIndicator()
            }
        }
        applyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    @objc private func sourceDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard Date() >= self.suppressChangeIndicatorUntil else { return }
            self.showIndicator()
        }
    }

    private func showIndicator() {
        guard settings.indicatorEnabled, let current else { return }
        indicator.show(badge: current.badge, korean: current.badge == "한",
                       duration: settings.indicatorDuration)
    }

    // MARK: - TIS 헬퍼

    private func property(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }
}
