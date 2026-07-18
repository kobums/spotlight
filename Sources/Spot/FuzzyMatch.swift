import Foundation

/// fzy 스타일 fuzzy 매칭. 단어 경계/camelCase/연속 매치에 보너스, 갭에 페널티.
/// 한글 초성 검색 지원: "ㅋㅋㅇ" → "카카오톡"
enum FuzzyMatch {

    private static let gapLeading = -0.005
    private static let gapTrailing = -0.005
    private static let gapInner = -0.01
    private static let matchConsecutive = 1.0
    private static let matchSlash = 0.9
    private static let matchWord = 0.8
    private static let matchCapital = 0.7
    private static let matchDot = 0.6
    private static let scoreMax = Double.infinity
    private static let scoreMin = -Double.infinity

    /// 매칭되면 점수(높을수록 좋음), 아니면 nil
    static func score(needle: String, haystack: String) -> Double? {
        if needle.isEmpty { return nil }

        let n = Array(needle.lowercased())
        let hOriginal = Array(haystack)
        let h = Array(haystack.lowercased())

        // 초성 검색: needle이 전부 한글 자음이면 haystack의 초성열과 비교
        if isAllChoseong(n) {
            let cho = choseongs(of: h)
            if isSubsequence(n, of: cho) {
                var s = 0.5
                if cho.starts(with: n) { s += 1.0 }
                return s
            }
            return nil
        }

        guard isSubsequence(n, of: h) else { return nil }

        if n.count == h.count {
            return scoreMax // 완전 일치
        }
        if h.count > 512 {
            return 0 // 너무 길면 매칭만 인정
        }

        let bonus = matchBonus(hOriginal: hOriginal, hLower: h)
        let N = n.count, M = h.count

        // fzy의 D(현재 문자가 매치로 끝나는 최적), M(전체 최적) 2행 DP
        var dPrev = [Double](repeating: scoreMin, count: M)
        var mPrev = [Double](repeating: scoreMin, count: M)
        var dCurr = [Double](repeating: scoreMin, count: M)
        var mCurr = [Double](repeating: scoreMin, count: M)

        for i in 0..<N {
            let gapScore = (i == N - 1) ? gapTrailing : gapInner
            var prevScore = scoreMin
            for j in 0..<M {
                if n[i] == h[j] {
                    var s = scoreMin
                    if i == 0 {
                        s = Double(j) * gapLeading + bonus[j]
                    } else if j > 0 {
                        s = max(
                            mPrev[j - 1] + bonus[j],
                            dPrev[j - 1] + matchConsecutive
                        )
                    }
                    dCurr[j] = s
                    prevScore = max(s, prevScore + gapScore)
                    mCurr[j] = prevScore
                } else {
                    dCurr[j] = scoreMin
                    prevScore += gapScore
                    mCurr[j] = prevScore
                }
            }
            swap(&dPrev, &dCurr)
            swap(&mPrev, &mCurr)
        }

        var result = mPrev[M - 1]
        // 접두사 일치 보너스
        if h.starts(with: n) { result += 1.5 }
        return result
    }

    private static func isSubsequence(_ needle: [Character], of haystack: [Character]) -> Bool {
        var i = 0
        for c in haystack where i < needle.count {
            if c == needle[i] { i += 1 }
        }
        return i == needle.count
    }

    private static func matchBonus(hOriginal: [Character], hLower: [Character]) -> [Double] {
        var bonus = [Double](repeating: 0, count: hLower.count)
        var prev: Character = "/"
        for (i, c) in hLower.enumerated() {
            if prev == "/" {
                bonus[i] = matchSlash
            } else if prev == "-" || prev == "_" || prev == " " {
                bonus[i] = matchWord
            } else if prev == "." {
                bonus[i] = matchDot
            } else if i < hOriginal.count,
                      hOriginal[i].isUppercase,
                      i > 0, hOriginal[i - 1].isLowercase {
                bonus[i] = matchCapital
            }
            prev = c
        }
        return bonus
    }

    // MARK: - 한글 초성

    private static let choseongList: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ",
        "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    private static func isAllChoseong(_ chars: [Character]) -> Bool {
        !chars.isEmpty && chars.allSatisfy { choseongList.contains($0) }
    }

    private static func choseongs(of chars: [Character]) -> [Character] {
        chars.compactMap { c in
            guard let scalar = c.unicodeScalars.first,
                  scalar.value >= 0xAC00, scalar.value <= 0xD7A3 else {
                return choseongList.contains(c) ? c : nil
            }
            let index = Int(scalar.value - 0xAC00) / (21 * 28)
            return choseongList[index]
        }
    }
}
