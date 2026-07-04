import Foundation

// fzf-style subsequence matcher. Returns nil when the query is not a
// subsequence of the candidate, otherwise a score in roughly 0...1.
enum FuzzyMatcher {

    static func score(query: String, candidate: String) -> Double? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let cLower = Array(candidate.lowercased())
        let cOrig = Array(candidate)
        if q.count > cLower.count { return nil }

        var qi = 0
        var raw = 0.0
        var lastMatch = -2
        var firstMatch = -1

        for ci in 0..<cLower.count {
            guard qi < q.count else { break }
            if cLower[ci] == q[qi] {
                var bonus = 1.0
                if ci == 0 {
                    bonus += 2.0                        // start of string
                } else {
                    let prev = cOrig[ci - 1]
                    if prev == " " || prev == "-" || prev == "_" || prev == "/" || prev == "." {
                        bonus += 1.6                    // start of word
                    } else if prev.isLowercase && cOrig[ci].isUppercase {
                        bonus += 1.2                    // camelCase boundary
                    }
                }
                if ci == lastMatch + 1 { bonus += 1.0 } // consecutive run
                raw += bonus
                if firstMatch < 0 { firstMatch = ci }
                lastMatch = ci
                qi += 1
            }
        }
        guard qi == q.count else { return nil }

        // Normalize: perfect dense prefix match approaches 1.0.
        let maxPossible = Double(q.count) * 4.0
        var s = raw / maxPossible
        // Prefer tighter spans and shorter candidates.
        let span = Double(lastMatch - firstMatch + 1)
        s *= 0.7 + 0.3 * (Double(q.count) / span)
        s *= 0.85 + 0.15 * min(1.0, 12.0 / Double(cLower.count))
        if candidate.lowercased() == query.lowercased() { s = max(s, 1.0) }
        return s
    }

    // Convenience: best score across several fields (e.g. name + keywords).
    static func score(query: String, fields: [String]) -> Double? {
        var best: Double?
        for f in fields {
            if let s = score(query: query, candidate: f) {
                best = max(best ?? 0, s)
            }
        }
        return best
    }
}
