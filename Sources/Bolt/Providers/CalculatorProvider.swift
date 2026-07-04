import AppKit

// Inline calculator (FR-7): arithmetic typed into the search field shows
// the result as the top row, Enter copies it. Also handles the
// "18% of 25000" GST-style phrasing.
final class CalculatorProvider: SearchProvider {
    let name = "Calculator"

    private static let percentOfPattern = try! NSRegularExpression(
        pattern: #"^([\d.,]+)\s*%\s*(?:of|on)\s*([\d.,]+)$"#,
        options: .caseInsensitive
    )

    func results(for query: Query) -> [ResultItem] {
        let text = query.trimmed
        guard !text.isEmpty else { return [] }

        // "18% of 25000" and "18% on 25000" (GST-style additions).
        let range = NSRange(text.startIndex..., in: text)
        if let match = Self.percentOfPattern.firstMatch(in: text, range: range),
           let pctRange = Range(match.range(at: 1), in: text),
           let baseRange = Range(match.range(at: 2), in: text),
           let pct = Double(text[pctRange].replacingOccurrences(of: ",", with: "")),
           let base = Double(text[baseRange].replacingOccurrences(of: ",", with: "")) {

            let isOn = text.lowercased().contains(" on ")
            let part = base * pct / 100.0
            let value = isOn ? base + part : part
            let detail = isOn
                ? "\(Self.format(base)) + \(pct.cleanString)% = adds \(Self.format(part))"
                : "\(pct.cleanString)% of \(Self.format(base))"
            return [item(result: value, subtitle: detail)]
        }

        guard ExpressionParser.looksLikeMath(text),
              let value = ExpressionParser.evaluate(text) else { return [] }
        return [item(result: value, subtitle: text)]
    }

    private func item(result: Double, subtitle: String) -> ResultItem {
        let formatted = Self.format(result)
        return ResultItem(
            id: "calc:result",
            title: formatted,
            subtitle: subtitle,
            icon: .symbol("equal.circle.fill"),
            kind: .calculator,
            score: 3.0,   // always the top row
            accessory: "⏎ copies",
            action: { _ in
                ClipboardManager.shared.ignoreNextChange = true
                PasteHelper.copy(text: formatted)
                return .toast("Copied \(formatted)")
            }
        )
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = abs(value) < 1 ? 8 : 4
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = abs(value) >= 10_000
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

extension Double {
    var cleanString: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", self)
            : String(self)
    }
}
