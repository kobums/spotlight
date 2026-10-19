import AppKit

/// 계산기 확장 — 날짜 계산·색상 변환·진법 변환. CalculatorProvider가 수식·단위보다 먼저 시도한다.
/// 모두 순수 함수라 기준일(`today`)을 주입해 확인할 수 있다.
enum CalculatorExtras {
    struct Answer: Equatable {
        let title: String
        var copy: String? = nil   // nil이면 title을 복사
        var note: String = ""
        var color: NSColor? = nil // 색상 변환이면 견본 아이콘
    }

    static func answer(_ text: String, today: Date = Date()) -> Answer? {
        relativeDate(text, today: today) ?? dDay(text, today: today) ?? untilDate(text, today: today)
            ?? color(text) ?? radix(text)
    }

    // MARK: - 날짜 ("3주 후", "D-100", "2026-12-25까지", "2026-03-01부터")

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// "2026-11-09 (월)" — 복사는 요일 없이
    private static func dateTitle(_ date: Date) -> (title: String, copy: String) {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "E"
        return ("\(day) (\(formatter.string(from: date)))", day)
    }

    private static func daysBetween(_ from: Date, _ to: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// "3주 후", "100일 뒤", "2개월 전", "1년후", "10 days later"
    static func relativeDate(_ text: String, today: Date) -> Answer? {
        let pattern = #"^(\d+)\s*(일|주|개월|달|년|days?|weeks?|months?|years?)\s*(후|뒤|전|later|after|ago|before)$"#
        guard let groups = match(pattern, text), let amount = Int(groups[1]) else { return nil }
        let component: Calendar.Component
        switch groups[2].lowercased() {
        case "일", "day", "days": component = .day
        case "주", "week", "weeks": component = .weekOfYear
        case "개월", "달", "month", "months": component = .month
        default: component = .year
        }
        let past = ["전", "ago", "before"].contains(groups[3].lowercased())
        guard let date = calendar.date(byAdding: component, value: past ? -amount : amount, to: today) else { return nil }
        let (title, copy) = dateTitle(date)
        let days = abs(daysBetween(today, date))
        let note = component == .day ? "Enter로 복사" : "\(past ? "\(days)일 전" : "\(days)일 뒤") · Enter로 복사"
        return Answer(title: title, copy: copy, note: note)
    }

    /// "D-100" → 오늘부터 100일 뒤가 D-day인 날짜
    static func dDay(_ text: String, today: Date) -> Answer? {
        guard let groups = match(#"^[dD]\s*-\s*(\d+)$"#, text), let days = Int(groups[1]),
              let date = calendar.date(byAdding: .day, value: days, to: today) else { return nil }
        let (title, copy) = dateTitle(date)
        return Answer(title: title, copy: copy, note: "오늘이 D-\(days)인 D-day · Enter로 복사")
    }

    /// "2026-12-25까지" → D-67, "2026-03-01부터" → 232일 지남. 연도를 빼면(`12-25까지`) 올해,
    /// `까지`인데 올해 날짜가 이미 지났으면 내년.
    static func untilDate(_ text: String, today: Date) -> Answer? {
        let pattern = #"^(?:(\d{4})[-./])?(\d{1,2})[-./](\d{1,2})\s*(까지|부터)$"#
        guard let groups = match(pattern, text),
              let month = Int(groups[2]), let day = Int(groups[3]) else { return nil }
        let since = groups[4] == "부터"
        let explicitYear = Int(groups[1])
        var components = DateComponents(year: explicitYear ?? calendar.component(.year, from: today), month: month, day: day)
        guard var date = calendar.date(from: components),
              calendar.component(.month, from: date) == month else { return nil } // 2/30 같은 날짜 거부
        if explicitYear == nil, !since, daysBetween(today, date) < 0 {
            components.year! += 1
            guard let next = calendar.date(from: components) else { return nil }
            date = next
        }
        let (dateText, _) = dateTitle(date)
        let days = daysBetween(today, date)
        if since {
            guard days <= 0 else {
                return Answer(title: "D-\(days)", note: "\(dateText)은 아직 \(days)일 남음 · Enter로 복사")
            }
            return Answer(title: "\(-days)일 지남", copy: String(-days),
                          note: "\(dateText)부터 오늘까지 · 시작일을 1일로 세면 \(-days + 1)일째")
        }
        switch days {
        case 0: return Answer(title: "D-day", note: "\(dateText) — 오늘 · Enter로 복사")
        case 1...: return Answer(title: "D-\(days)", note: "\(dateText)까지 \(days)일 남음 · Enter로 복사")
        default: return Answer(title: "D+\(-days)", note: "\(dateText)부터 \(-days)일 지남 · Enter로 복사")
        }
    }

    // MARK: - 색상 ("#ff5500 to rgb", "rgb(255,85,0) to hex", "#f50")

    private struct RGB { let r: Int, g: Int, b: Int }

    static func color(_ text: String) -> Answer? {
        var source = text
        var target: String?
        if let groups = match(#"^(.+?)\s+(?:to|in|->|→)\s+(rgb|hex|hsl)$"#, text) {
            source = groups[1]
            target = groups[2].lowercased()
        }
        let parsed: (RGB, String)
        if let rgb = parseHex(source) {
            parsed = (rgb, "hex")
        } else if let rgb = parseRGB(source) {
            parsed = (rgb, "rgb")
        } else if let rgb = parseHSL(source) {
            parsed = (rgb, "hsl")
        } else {
            return nil
        }
        let (rgb, from) = parsed
        // 대상이 없으면 hex는 rgb로, 나머지는 hex로
        let to = target ?? (from == "hex" ? "rgb" : "hex")
        let formats = ["hex": hexString(rgb), "rgb": "rgb(\(rgb.r), \(rgb.g), \(rgb.b))", "hsl": hslString(rgb)]
        let others = ["hex", "rgb", "hsl"].filter { $0 != to }.compactMap { formats[$0] }
        let swatch = NSColor(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255,
                             blue: CGFloat(rgb.b) / 255, alpha: 1)
        return Answer(title: formats[to]!, note: others.joined(separator: " · ") + " · Enter로 복사", color: swatch)
    }

    private static func parseHex(_ text: String) -> RGB? {
        guard let groups = match(#"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$"#, text) else { return nil }
        var hex = groups[1]
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard let value = Int(hex, radix: 16) else { return nil }
        return RGB(r: value >> 16 & 0xFF, g: value >> 8 & 0xFF, b: value & 0xFF)
    }

    private static func parseRGB(_ text: String) -> RGB? {
        guard let groups = match(#"^rgba?\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*(?:[,/]\s*[\d.]+%?\s*)?\)$"#, text),
              let r = Int(groups[1]), let g = Int(groups[2]), let b = Int(groups[3]),
              [r, g, b].allSatisfy({ (0...255).contains($0) }) else { return nil }
        return RGB(r: r, g: g, b: b)
    }

    private static func parseHSL(_ text: String) -> RGB? {
        guard let groups = match(#"^hsl\(\s*([\d.]+)\s*[, ]\s*([\d.]+)%\s*[, ]\s*([\d.]+)%\s*\)$"#, text),
              let h = Double(groups[1]), let s = Double(groups[2]), let l = Double(groups[3]),
              s <= 100, l <= 100 else { return nil }
        // CSS 명세의 HSL → RGB
        let sat = s / 100, light = l / 100
        func channel(_ n: Double) -> Int {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            let a = sat * min(light, 1 - light)
            let value = light - a * max(-1, min(k - 3, 9 - k, 1))
            return Int((value * 255).rounded())
        }
        return RGB(r: channel(0), g: channel(8), b: channel(4))
    }

    private static func hexString(_ c: RGB) -> String {
        String(format: "#%02X%02X%02X", c.r, c.g, c.b)
    }

    private static func hslString(_ c: RGB) -> String {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let maxV = max(r, g, b), minV = min(r, g, b), delta = maxV - minV
        let l = (maxV + minV) / 2
        var h = 0.0, s = 0.0
        if delta > 0 {
            s = delta / (1 - abs(2 * l - 1))
            switch maxV {
            case r: h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: h = 60 * ((b - r) / delta + 2)
            default: h = 60 * ((r - g) / delta + 4)
            }
            if h < 0 { h += 360 }
        }
        return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }

    // MARK: - 진법 ("0x1f", "0b1010", "0o17", "255 to hex", "0x1f to bin")

    static func radix(_ text: String) -> Answer? {
        var source = text
        var target: Int?
        if let groups = match(#"^(\S+)\s+(?:to|in|->|→)\s+(\S+)$"#, text) {
            guard let base = targetRadix(groups[2].lowercased()) else { return nil }
            source = groups[1]
            target = base
        }
        guard let (value, sourceBase) = parseInteger(source, allowDecimal: target != nil) else { return nil }
        // 대상이 없으면(리터럴 단독) 10진수로
        let to = target ?? 10
        let all = [(16, "0x"), (2, "0b"), (8, "0o"), (10, "")]
        let others = all.filter { $0.0 != to && $0.0 != sourceBase }.map { literal(value, base: $0.0) }
        return Answer(title: literal(value, base: to), note: (others + ["Enter로 복사"]).joined(separator: " · "))
    }

    private static func targetRadix(_ word: String) -> Int? {
        switch word {
        case "hex", "hexadecimal", "16진수", "16진법": return 16
        case "bin", "binary", "2진수", "2진법": return 2
        case "oct", "octal", "8진수", "8진법": return 8
        case "dec", "decimal", "10진수", "10진법": return 10
        default: return nil
        }
    }

    /// 접두 리터럴(0x·0b·0o) 또는 (to 변환일 때만) 10진 정수
    private static func parseInteger(_ text: String, allowDecimal: Bool) -> (UInt64, Int)? {
        let lower = text.lowercased().replacingOccurrences(of: "_", with: "")
        for (prefix, base) in [("0x", 16), ("0b", 2), ("0o", 8)] where lower.hasPrefix(prefix) {
            let digits = lower.dropFirst(2)
            guard !digits.isEmpty, let value = UInt64(digits, radix: base) else { return nil }
            return (value, base)
        }
        guard allowDecimal, let value = UInt64(lower.replacingOccurrences(of: ",", with: "")) else { return nil }
        return (value, 10)
    }

    private static func literal(_ value: UInt64, base: Int) -> String {
        switch base {
        case 16: return "0x" + String(value, radix: 16, uppercase: true)
        case 2: return "0b" + String(value, radix: 2)
        case 8: return "0o" + String(value, radix: 8)
        default: return String(value)
        }
    }

    // MARK: - 공통

    /// 정규식 전체 일치 시 캡처 그룹들 (0번 = 전체, 없는 그룹은 빈 문자열)
    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
