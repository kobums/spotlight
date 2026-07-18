/// Vimium식 힌트 라벨 생성. 홈로우 키를 앞세운 알파벳으로,
/// 서로 접두어 관계가 생기지 않도록 균일한 길이의 라벨을 만든다.
enum HintLabeler {
    private static let alphabet = Array("ASDFGHJKLQWERTYUIOPZXCVBNM")

    static func labels(count: Int) -> [String] {
        guard count > 0 else { return [] }
        let base = alphabet.count
        var length = 1
        var capacity = base
        while capacity < count {
            length += 1
            capacity *= base
        }

        var result: [String] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            var label = ""
            var value = i
            for _ in 0..<length {
                label = String(alphabet[value % base]) + label
                value /= base
            }
            result.append(label)
        }
        return result
    }
}
