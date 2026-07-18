import AppKit

/// 수식 계산 + 단위 변환. 결과는 Enter로 클립보드에 복사.
final class CalculatorProvider: SearchProvider {

    func results(for query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        if let converted = unitConversion(trimmed) {
            return [makeResult(text: converted, original: trimmed)]
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

    private func makeResult(text: String, original: String) -> SearchResult {
        SearchResult(
            id: "calc:\(original)",
            kind: .calculator,
            title: text,
            subtitle: "\(original) — Enter로 복사",
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

    // MARK: - 단위 변환 ("10km to mi", "30c to f")

    private func unitConversion(_ text: String) -> String? {
        let pattern = #"^(-?[\d.,]+)\s*([a-zA-Z°℃℉]+)\s+(?:to|in|as|->|→)\s+([a-zA-Z°℃℉]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(match.range(at: 1), in: text),
              let fromRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text) else { return nil }

        let numString = text[numRange].replacingOccurrences(of: ",", with: "")
        guard let value = Double(numString),
              let fromUnit = Self.unit(String(text[fromRange]).lowercased()),
              let toUnit = Self.unit(String(text[toRange]).lowercased()) else { return nil }

        // 같은 물리량(예: 둘 다 UnitLength)끼리만 변환
        guard type(of: fromUnit) == type(of: toUnit) else { return nil }
        let base = fromUnit.converter.baseUnitValue(fromValue: value)
        let convertedValue = toUnit.converter.value(fromBaseUnitValue: base)
        return "\(format(convertedValue)) \(toUnit.symbol)"
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
        default: return nil
        }
    }
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
