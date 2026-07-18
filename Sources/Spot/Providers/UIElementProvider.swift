import AppKit

/// ";" 접두사로 진입하는 최전면 앱 UI 요소 검색 (Shortcat 방식).
/// 접근성 트리를 비동기 수집·캐시하고, 요소 이름을 fuzzy 매칭해 Enter로 클릭한다.
final class UIElementProvider {
    static func isElementQuery(_ query: String) -> Bool {
        query.hasPrefix(";")
    }

    /// 수집이 비동기라 결과는 항상 콜백으로 전달 (메인 스레드)
    var onResults: (([SearchResult]) -> Void)?

    private var cachedTargets: [HintTarget] = []
    private var cachedPid: pid_t = -1
    private var cachedAt = Date.distantPast
    private let cacheLifetime: TimeInterval = 5
    private var isCollecting = false
    private var pendingTerm: String?

    func search(_ query: String) {
        guard Self.isElementQuery(query) else { return }
        guard AccessibilityPermission.ensureTrusted() else {
            deliver([])
            return
        }
        let term = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
        let pid = HintTargetCollector.frontmostApp()?.processIdentifier ?? -1

        if pid == cachedPid, Date().timeIntervalSince(cachedAt) < cacheLifetime {
            deliver(results(matching: term))
            return
        }

        pendingTerm = term
        guard !isCollecting else { return }
        isCollecting = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let collection = HintTargetCollector.collectFrontmost()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCollecting = false
                self.cachedTargets = collection?.targets ?? []
                self.cachedPid = pid
                self.cachedAt = Date()
                if let pending = self.pendingTerm {
                    self.pendingTerm = nil
                    self.onResults?(self.results(matching: pending))
                }
            }
        }
    }

    /// 항상 다음 런루프에 전달 — syncResults 반환값이 콜백 결과를 덮어쓰지 않게
    private func deliver(_ results: [SearchResult]) {
        DispatchQueue.main.async { [weak self] in
            self?.onResults?(results)
        }
    }

    private func results(matching term: String) -> [SearchResult] {
        let named = cachedTargets.filter { !$0.name.isEmpty }
        let matched: [HintTarget]
        if term.isEmpty {
            matched = Array(named.prefix(30))
        } else {
            matched = named
                .compactMap { target in
                    FuzzyMatch.score(needle: term, haystack: target.name).map { (target, $0) }
                }
                .sorted { $0.1 > $1.1 }
                .prefix(30)
                .map { $0.0 }
        }

        return matched.enumerated().map { index, target in
            SearchResult(
                id: "ui:\(Int(target.frame.midX)),\(Int(target.frame.midY))",
                kind: .uiElement,
                title: target.name,
                subtitle: Self.roleNames[target.role] ?? "요소",
                symbolName: Self.roleSymbols[target.role] ?? "cursorarrow.rays",
                score: -Double(index), // 전용 모드라 내부 순서만 유지
                action: { _ in
                    // 패널이 내려가고 원래 앱으로 포커스가 돌아간 뒤 실행
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        HintActionPerformer.perform(target)
                    }
                }
            )
        }
    }

    private static let roleNames: [String: String] = [
        "AXButton": "버튼", "AXLink": "링크", "AXMenuItem": "메뉴 항목", "AXMenuBarItem": "메뉴",
        "AXMenuButton": "메뉴 버튼", "AXCheckBox": "체크박스", "AXRadioButton": "라디오 버튼",
        "AXPopUpButton": "팝업 버튼", "AXComboBox": "콤보 박스", "AXTextField": "입력란",
        "AXTextArea": "텍스트 영역", "AXSearchField": "검색 필드", "AXSlider": "슬라이더",
        "AXTabButton": "탭", "AXCell": "셀", "AXSwitch": "스위치",
        "AXDisclosureTriangle": "펼침", "AXIncrementor": "스테퍼", "AXColorWell": "색상",
    ]

    private static let roleSymbols: [String: String] = [
        "AXButton": "hand.point.up.left", "AXLink": "link",
        "AXTextField": "character.cursor.ibeam", "AXTextArea": "character.cursor.ibeam",
        "AXSearchField": "magnifyingglass", "AXMenuBarItem": "filemenu.and.selection",
        "AXMenuItem": "filemenu.and.selection", "AXMenuButton": "filemenu.and.selection",
        "AXCheckBox": "checkmark.square", "AXRadioButton": "circle.circle",
        "AXTabButton": "rectangle.topthird.inset.filled", "AXSlider": "slider.horizontal.3",
    ]
}
