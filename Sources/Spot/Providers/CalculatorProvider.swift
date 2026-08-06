import AppKit

/// 수식 계산 + 단위 변환. 결과는 Enter로 클립보드에 복사.
final class CalculatorProvider: SearchProvider {

    func results(for query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        if let (converted, note) = conversion(trimmed) ?? singleQuantity(trimmed) {
            return [makeResult(text: converted, original: trimmed, note: note)]
        }

        // 숫자와 연산자로만 구성된 경우에만 계산 시도
        let mathChars = CharacterSet(charactersIn: "0123456789.,+-*/^%() ")
        let looksLikeMath = trimmed.unicodeScalars.allSatisfy { mathChars.contains($0) }
            && trimmed.rangeOfCharacter(from: .decimalDigits) != nil
            && trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%")) != nil

        guard looksLikeMath else { return [] }
        guard let value = ExpressionParser(trimmed.replacingOccurrences(of: ",", with: "")).parse() else {
            return []
        }
        return [makeResult(text: format(value), original: trimmed)]
    }

    private func makeResult(text: String, original: String, note: String = "") -> SearchResult {
        SearchResult(
            id: "calc:\(original)",
            kind: .calculator,
            title: text,
            subtitle: note.isEmpty ? "\(original) — Enter로 복사" : "\(original) — \(note)",
            symbolName: "equal.circle.fill",
            score: Score.calculator, // 계산 결과는 항상 최상단
            action: { _ in
                ClipboardStore.shared.copy(text)
            }
        )
    }

    private func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - 단위·환율 변환 ("10km to mi", "30c to f", "100달러 to 원")

    /// (변환 결과, 부가 설명) — 환율이면 기준일을 설명에 담는다
    private func conversion(_ text: String) -> (String, String)? {
        let pattern = #"^(-?[\d.,]+)\s*([a-zA-Z0-9°℃℉㎡₩$€¥£/가-힣]+)\s+(?:to|in|as|->|→)\s+([a-zA-Z0-9°℃℉㎡₩$€¥£/가-힣]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(match.range(at: 1), in: text),
              let fromRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text) else { return nil }

        let numString = text[numRange].replacingOccurrences(of: ",", with: "")
        guard let value = Double(numString) else { return nil }
        let from = String(text[fromRange]).lowercased()
        let to = String(text[toRange]).lowercased()

        if let converted = currencyConversion(value, from: from, to: to) {
            return converted
        }

        guard let fromUnit = Self.unit(from), let toUnit = Self.unit(to) else { return nil }
        // 같은 물리량(예: 둘 다 UnitLength)끼리만 변환. 내장 유닛은 비공개 서브클래스
        // 인스턴스일 수 있어 type(of:) 직접 비교 대신 양방향 isKind(of:)로 확인한다.
        guard fromUnit.isKind(of: type(of: toUnit)) || toUnit.isKind(of: type(of: fromUnit)) else {
            return nil
        }
        let base = fromUnit.converter.baseUnitValue(fromValue: value)
        let convertedValue = toUnit.converter.value(fromBaseUnitValue: base)
        return ("\(format(convertedValue)) \(toUnit.symbol)", "")
    }

    // MARK: - 단독 수량 ("1000$", "100평" — to 없이 기본 대상으로 변환)

    /// 통화는 원으로(원이면 달러로), 단위는 defaultUnitTargets의 짝으로 변환
    private func singleQuantity(_ text: String) -> (String, String)? {
        let pattern = #"^(-?[\d.,]+)\s*([a-zA-Z0-9°℃℉㎡₩$€¥£/가-힣]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        guard let value = Double(text[numRange].replacingOccurrences(of: ",", with: "")) else {
            return nil
        }
        let token = String(text[unitRange]).lowercased()

        if let code = currencyCode(token) {
            return currencyConversion(value, from: token, to: code == "KRW" ? "usd" : "krw")
        }

        guard let target = Self.defaultUnitTargets[token],
              let fromUnit = Self.unit(token), let toUnit = Self.unit(target) else { return nil }
        let base = fromUnit.converter.baseUnitValue(fromValue: value)
        let converted = toUnit.converter.value(fromBaseUnitValue: base)
        return ("\(format(converted)) \(toUnit.symbol)", "")
    }

    /// 단독 수량 입력의 기본 변환 대상 (임페리얼 → 미터법, 평 ↔ ㎡)
    private static let defaultUnitTargets: [String: String] = [
        "평": "m2", "m2": "평", "㎡": "평", "제곱미터": "평",
        "mi": "km", "mile": "km", "miles": "km",
        "ft": "m", "feet": "m",
        "in": "cm", "inch": "cm", "inches": "cm",
        "yd": "m", "yard": "m",
        "lb": "kg", "lbs": "kg", "pound": "kg",
        "oz": "g",
        "f": "c", "°f": "c", "℉": "c", "fahrenheit": "c",
        "gal": "l", "gallon": "l",
    ]

    // MARK: - 환율

    private static let currencyAliases: [String: String] = [
        "원": "KRW", "₩": "KRW",
        "달러": "USD", "불": "USD", "$": "USD",
        "유로": "EUR", "€": "EUR",
        "엔": "JPY", "¥": "JPY",
        "위안": "CNY", "위엔": "CNY",
        "파운드": "GBP", "£": "GBP",
    ]

    /// 별칭 또는 ISO 코드(krw·usd …)를 시세표에 있는 통화코드로 해석
    private func currencyCode(_ s: String) -> String? {
        if let code = Self.currencyAliases[s] { return code }
        guard s.count == 3, s.allSatisfy({ $0.isLetter && $0.isASCII }),
              CurrencyRates.shared.rate(s) != nil else { return nil }
        return s.uppercased()
    }

    private func currencyConversion(_ value: Double, from: String, to: String) -> (String, String)? {
        guard let fromCode = currencyCode(from), let toCode = currencyCode(to),
              let fromRate = CurrencyRates.shared.rate(fromCode),
              let toRate = CurrencyRates.shared.rate(toCode) else { return nil }
        let converted = value / fromRate * toRate
        var note = "환율"
        if let asOf = CurrencyRates.shared.asOf {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            note = "환율 \(formatter.string(from: asOf)) 기준"
        }
        return ("\(format(converted)) \(toCode)", note)
    }

    private static func unit(_ s: String) -> Dimension? {
        switch s {
        // 길이
        case "km": return UnitLength.kilometers
        case "m": return UnitLength.meters
        case "cm": return UnitLength.centimeters
        case "mm": return UnitLength.millimeters
        case "mi", "mile", "miles": return UnitLength.miles
        case "ft", "feet": return UnitLength.feet
        case "in", "inch", "inches": return UnitLength.inches
        case "yd", "yard": return UnitLength.yards
        // 무게
        case "kg": return UnitMass.kilograms
        case "g": return UnitMass.grams
        case "mg": return UnitMass.milligrams
        case "lb", "lbs", "pound": return UnitMass.pounds
        case "oz": return UnitMass.ounces
        case "t", "ton": return UnitMass.metricTons
        // 온도
        case "c", "°c", "℃", "celsius": return UnitTemperature.celsius
        case "f", "°f", "℉", "fahrenheit": return UnitTemperature.fahrenheit
        case "k", "kelvin": return UnitTemperature.kelvin
        // 부피
        case "l", "liter", "liters": return UnitVolume.liters
        case "ml": return UnitVolume.milliliters
        case "gal", "gallon": return UnitVolume.gallons
        // 데이터
        case "kb": return UnitInformationStorage.kilobytes
        case "mb": return UnitInformationStorage.megabytes
        case "gb": return UnitInformationStorage.gigabytes
        case "tb": return UnitInformationStorage.terabytes
        // 면적
        case "m2", "㎡", "제곱미터": return UnitArea.squareMeters
        case "km2": return UnitArea.squareKilometers
        case "ft2": return UnitArea.squareFeet
        case "ha", "헥타르": return UnitArea.hectares
        case "acre", "acres": return UnitArea.acres
        case "평": return pyeong
        // 속도
        case "km/h", "kmh", "kph": return UnitSpeed.kilometersPerHour
        case "mph": return UnitSpeed.milesPerHour
        case "m/s", "mps": return UnitSpeed.metersPerSecond
        case "kt", "knot", "knots", "노트": return UnitSpeed.knots
        // 시간
        case "s", "sec", "초": return UnitDuration.seconds
        case "min", "분": return UnitDuration.minutes
        case "h", "hr", "hour", "hours", "시간": return UnitDuration.hours
        case "d", "day", "days", "일": return days
        case "w", "week", "weeks", "주": return weeks
        default: return nil
        }
    }

    /// Foundation에 없는 단위 — 1평 = 3.3057851㎡, 하루 = 86,400초
    private static let pyeong = UnitArea(symbol: "평", converter: UnitConverterLinear(coefficient: 3.3057851))
    private static let days = UnitDuration(symbol: "일", converter: UnitConverterLinear(coefficient: 86400))
    private static let weeks = UnitDuration(symbol: "주", converter: UnitConverterLinear(coefficient: 604800))
}

/// 사칙연산 + 거듭제곱 + 괄호를 지원하는 재귀 하강 파서
private final class ExpressionParser {
    private let chars: [Character]
    private var pos = 0

    init(_ text: String) {
        chars = Array(text.replacingOccurrences(of: " ", with: ""))
    }

    func parse() -> Double? {
        guard let value = parseAddSub(), pos == chars.count else { return nil }
        return value.isFinite ? value : nil
    }

    private func parseAddSub() -> Double? {
        guard var left = parseMulDiv() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            pos += 1
            guard let right = parseMulDiv() else { return nil }
            left = op == "+" ? left + right : left - right
        }
        return left
    }

    private func parseMulDiv() -> Double? {
        guard var left = parsePower() else { return nil }
        while let op = peek(), op == "*" || op == "/" || op == "%" {
            pos += 1
            guard let right = parsePower() else { return nil }
            switch op {
            case "*": left *= right
            case "/": left /= right
            default: left = left.truncatingRemainder(dividingBy: right)
            }
        }
        return left
    }

    private func parsePower() -> Double? {
        guard let base = parseUnary() else { return nil }
        if peek() == "^" {
            pos += 1
            guard let exp = parsePower() else { return nil } // 우결합
            return pow(base, exp)
        }
        return base
    }

    private func parseUnary() -> Double? {
        if peek() == "-" {
            pos += 1
            return parseUnary().map { -$0 }
        }
        return parsePrimary()
    }

    private func parsePrimary() -> Double? {
        if peek() == "(" {
            pos += 1
            guard let value = parseAddSub(), peek() == ")" else { return nil }
            pos += 1
            return value
        }
        var numStr = ""
        while let c = peek(), c.isNumber || c == "." {
            numStr.append(c)
            pos += 1
        }
        return Double(numStr)
    }

    private func peek() -> Character? {
        pos < chars.count ? chars[pos] : nil
    }
}
