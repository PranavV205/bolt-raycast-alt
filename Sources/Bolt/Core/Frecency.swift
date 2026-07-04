import Foundation

// Tracks how often and how recently each result id was chosen, so the
// things you actually use float to the top (FR-4).
final class Frecency {
    static let shared = Frecency()

    private struct Entry: Codable {
        var uses: Int
        var last: Date
    }

    private var entries: [String: Entry] = [:]
    private let queue = DispatchQueue(label: "bolt.frecency")

    private init() {
        if let data = try? Data(contentsOf: AppPaths.frecencyFile),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    func recordUse(id: String) {
        var e = entries[id] ?? Entry(uses: 0, last: Date())
        e.uses += 1
        e.last = Date()
        entries[id] = e
        persist()
    }

    // Multiplier applied on top of the fuzzy match score.
    func boost(id: String) -> Double {
        guard let e = entries[id] else { return 0 }
        let useBoost = min(Double(e.uses), 20.0) * 0.04
        let age = Date().timeIntervalSince(e.last)
        let recencyBoost: Double
        switch age {
        case ..<3600: recencyBoost = 0.5
        case ..<86_400: recencyBoost = 0.3
        case ..<604_800: recencyBoost = 0.15
        default: recencyBoost = 0.05
        }
        return useBoost + recencyBoost
    }

    // Ids ordered by frecency, used for the empty-query default list.
    func topIds(limit: Int) -> [String] {
        entries
            .sorted { a, b in
                let sa = Double(a.value.uses) + max(0, 7 - Date().timeIntervalSince(a.value.last) / 86_400)
                let sb = Double(b.value.uses) + max(0, 7 - Date().timeIntervalSince(b.value.last) / 86_400)
                return sa > sb
            }
            .prefix(limit)
            .map(\.key)
    }

    private func persist() {
        let snapshot = entries
        queue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: AppPaths.frecencyFile)
            }
        }
    }
}
