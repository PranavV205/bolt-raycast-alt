import Foundation

// Daily exchange rates from frankfurter.app (ECB data, no API key).
// This is the only network call in the entire app. Rates are cached on
// disk for 24 hours; conversion always reads the cache.
final class CurrencyService {
    static let shared = CurrencyService()

    private struct CachedRates: Codable {
        let base: String
        let date: String
        let rates: [String: Double]
        let fetchedAt: Date
    }

    private var cache: CachedRates?
    private var fetching = false

    static let knownCodes: Set<String> = [
        "usd", "eur", "gbp", "inr", "jpy", "cny", "aud", "cad", "chf", "hkd",
        "sgd", "krw", "sek", "nok", "dkk", "nzd", "mxn", "brl", "zar", "try",
        "aed", "thb", "myr", "idr", "php", "pln", "czk", "huf", "ils", "ron",
    ]

    static let symbolMap: [String: String] = [
        "$": "usd", "€": "eur", "£": "gbp", "₹": "inr", "¥": "jpy", "₩": "krw",
    ]

    private init() {
        if let data = try? Data(contentsOf: AppPaths.ratesFile),
           let decoded = try? JSONDecoder().decode(CachedRates.self, from: data) {
            cache = decoded
        }
    }

    var hasRates: Bool { cache != nil }
    var ratesDate: String? { cache?.date }

    func refreshIfStale() {
        guard AppConfig.shared.currencyEnabled else { return }
        if let cache, Date().timeIntervalSince(cache.fetchedAt) < 86_400 { return }
        guard !fetching else { return }
        fetching = true

        let url = URL(string: "https://api.frankfurter.app/latest?base=USD")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            defer { self?.fetching = false }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json["rates"] as? [String: Double],
                  let date = json["date"] as? String else { return }

            var all = rates
            all["USD"] = 1.0
            let cached = CachedRates(base: "USD", date: date, rates: all, fetchedAt: Date())
            DispatchQueue.main.async {
                self?.cache = cached
            }
            if let encoded = try? JSONEncoder().encode(cached) {
                try? encoded.write(to: AppPaths.ratesFile)
            }
        }.resume()
    }

    // Convert via USD as the pivot currency.
    func convert(amount: Double, from: String, to: String) -> Double? {
        guard let cache else { return nil }
        let fromCode = from.uppercased()
        let toCode = to.uppercased()
        guard let fromRate = cache.rates[fromCode], let toRate = cache.rates[toCode] else { return nil }
        return amount / fromRate * toRate
    }
}
