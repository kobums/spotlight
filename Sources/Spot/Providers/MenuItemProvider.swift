import AppKit
import ApplicationServices

/// ">" 접두사로 진입하는 최전면 앱 메뉴 항목 검색 (Paletro 방식).
/// 메뉴바를 AX로 스캔·캐시하고, 항목 이름을 fuzzy 매칭해 Enter로 실행한다.
final class MenuItemProvider {
    static func isMenuQuery(_ query: String) -> Bool {
        query.hasPrefix(">")
    }

    /// 수집이 비동기라 결과는 항상 콜백으로 전달 (메인 스레드)
    var onResults: (([SearchResult]) -> Void)?

    private struct Item {
        let element: AXUIElement
        let title: String
        let path: String      // "파일 › 내보내기" (자기 자신 제외)
        let shortcut: String  // "⇧⌘S" 또는 ""
    }

    private var cached: [Item] = []
    private var cachedPid: pid_t = -1
    private var cachedAt = Date.distantPast
    private let cacheLifetime: TimeInterval = 10
    private var isCollecting = false
    private var pendingTerm: String?
    private var appBundleID = ""

    func search(_ query: String) {
        guard Self.isMenuQuery(query) else { return }
        guard AccessibilityPermission.ensureTrusted() else {
            deliver([])
            return
        }
        let term = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
        let app = HintTargetCollector.frontmostApp()
        let pid = app?.processIdentifier ?? -1

        if pid == cachedPid, Date().timeIntervalSince(cachedAt) < cacheLifetime {
            deliver(results(matching: term))
            return
        }

        appBundleID = app?.bundleIdentifier ?? ""
        pendingTerm = term
        guard !isCollecting else { return }
        isCollecting = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let items = Self.collect(pid: pid)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCollecting = false
                self.cached = items
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
        let matched: [Item]
        if term.isEmpty {
            matched = Array(cached.prefix(30))
        } else {
            matched = cached
                .compactMap { item -> (Item, Double)? in
                    let scores = [
                        FuzzyMatch.score(needle: term, haystack: item.title),
                        FuzzyMatch.score(needle: term, haystack: "\(item.path) \(item.title)"),
                    ].compactMap { $0 }
                    guard let best = scores.max() else { return nil }
                    return (item, best)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(30)
                .map { $0.0 }
        }

        let bundleID = appBundleID
        return matched.enumerated().map { index, item in
            let subtitle = item.shortcut.isEmpty ? item.path : "\(item.path)   \(item.shortcut)"
            return SearchResult(
                id: "menu:\(bundleID):\(item.path)>\(item.title)",
                kind: .menuItem,
                title: item.title,
                subtitle: subtitle,
                symbolName: "filemenu.and.selection",
                score: -Double(index), // 전용 모드라 내부 순서만 유지
                action: { _ in
                    // 패널이 내려가고 원래 앱으로 포커스가 돌아간 뒤 실행
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        AXUIElementPerformAction(item.element, kAXPressAction as CFString)
                    }
                }
            )
        }
    }

    // MARK: - 메뉴바 수집

    private static func collect(pid: pid_t) -> [Item] {
        guard pid > 0 else { return [] }
        let app = AXUIElementCreateApplication(pid)
        guard let menuBar = AX.element(AX.attribute(app, kAXMenuBarAttribute as String)) else {
            return []
        }
        var items: [Item] = []
        // 첫 번째는 Apple 메뉴 — 앱 고유 기능이 아니라 제외
        for top in children(of: menuBar).dropFirst() {
            guard let topTitle = title(of: top), !topTitle.isEmpty else { continue }
            for menu in children(of: top) {
                walk(menu, path: topTitle, into: &items, depth: 0)
            }
        }
        return items
    }

    private static func walk(_ menu: AXUIElement, path: String, into items: inout [Item], depth: Int) {
        guard depth < 5, items.count < 3000 else { return }
        for item in children(of: menu) {
            guard let itemTitle = title(of: item), !itemTitle.isEmpty else { continue } // 구분선 제외
            let submenus = children(of: item)
            if submenus.isEmpty {
                let enabled = (AX.attribute(item, kAXEnabledAttribute as String) as? Bool) ?? true
                guard enabled else { continue }
                items.append(Item(
                    element: item, title: itemTitle, path: path, shortcut: shortcut(of: item)))
            } else {
                for submenu in submenus {
                    walk(submenu, path: "\(path) › \(itemTitle)", into: &items, depth: depth + 1)
                }
            }
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let list = AX.attribute(element, kAXChildrenAttribute as String) as? [AnyObject] else {
            return []
        }
        return list.compactMap { AX.element($0) }
    }

    private static func title(of element: AXUIElement) -> String? {
        AX.attribute(element, kAXTitleAttribute as String) as? String
    }

    /// "⇧⌘S" 형식의 단축키 문자열 (없으면 "")
    private static func shortcut(of element: AXUIElement) -> String {
        guard let char = AX.attribute(element, "AXMenuItemCmdChar") as? String, !char.isEmpty else {
            return ""
        }
        let modifiers = (AX.attribute(element, "AXMenuItemCmdModifiers") as? Int) ?? 0
        var parts = ""
        if modifiers & 4 != 0 { parts += "⌃" }
        if modifiers & 2 != 0 { parts += "⌥" }
        if modifiers & 1 != 0 { parts += "⇧" }
        if modifiers & 8 == 0 { parts += "⌘" }  // 8 = Cmd 없음
        return parts + char.uppercased()
    }
}
