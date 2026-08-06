import Foundation

/// 환율 시세 캐시. open.er-api.com에서 USD 기준 시세를 받아 디스크에 보관하고
/// 24시간 지나면 백그라운드로 갱신한다. 조회는 항상 캐시에서 동기로 응답.
final class CurrencyRates {
    static let shared = CurrencyRates()

    struct Snapshot: Codable {
        let date: Date
        let rates: [String: Double]  // 통화코드 → 1 USD당 환율
    }

    private let store = JSONFileStore<Snapshot>(filename: "currency-rates.json", saveDelay: 0.1)
    private(set) var snapshot: Snapshot?
    private var isFetching = false

    private init() {
        snapshot = store.load()
        refreshIfStale()
    }

    /// 통화코드(대소문자 무관) → USD 기준 환율. 시세가 없으면 nil.
    func rate(_ code: String) -> Double? {
        refreshIfStale()
        return snapshot?.rates[code.uppercased()]
    }

    var asOf: Date? { snapshot?.date }

    private func refreshIfStale() {
        let stale = snapshot.map { Date().timeIntervalSince($0.date) > 24 * 3600 } ?? true
        guard stale, !isFetching else { return }
        isFetching = true
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rates = json["rates"] as? [String: Double], !rates.isEmpty else { return }
                let snap = Snapshot(date: Date(), rates: rates)
                self.snapshot = snap
                self.store.scheduleSave(snap)
            }
        }.resume()
    }
}
