import AppKit
import CoreServices

// "define <word>" via the built-in system dictionary. Enter opens the
// full entry in Dictionary.app.
final class DictionaryProvider {

    func define(_ word: String) -> [ResultItem] {
        let term = word.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return [] }

        let range = CFRange(location: 0, length: term.utf16.count)
        let definition = DCSCopyTextDefinition(nil, term as CFString, range)?
            .takeRetainedValue() as String?

        guard let definition, !definition.isEmpty else {
            return [ResultItem(
                id: "define:none",
                title: "No definition for \"\(term)\"",
                subtitle: "Enter searches Dictionary.app anyway",
                icon: .symbol("character.book.closed"),
                kind: .definition,
                score: 1.0,
                action: { _ in
                    Self.openDictionaryApp(term: term)
                    return .dismiss
                }
            )]
        }

        // The raw definition is one long line; split into digestible rows.
        let compact = definition
            .replacingOccurrences(of: "▶", with: " ▶ ")
            .replacingOccurrences(of: "  ", with: " ")

        var items: [ResultItem] = [ResultItem(
            id: "define:\(term)",
            title: term,
            subtitle: String(compact.prefix(160)),
            icon: .symbol("character.book.closed.fill"),
            kind: .definition,
            score: 2.0,
            accessory: "⏎ opens Dictionary",
            action: { _ in
                Self.openDictionaryApp(term: term)
                return .dismiss
            }
        )]

        if compact.count > 160 {
            items.append(ResultItem(
                id: "define:\(term):more",
                title: String(compact.dropFirst(160).prefix(160)),
                subtitle: "continued",
                icon: .symbol("text.justify.left"),
                kind: .definition,
                score: 1.9,
                action: { _ in
                    Self.openDictionaryApp(term: term)
                    return .dismiss
                }
            ))
        }
        return items
    }

    private static func openDictionaryApp(term: String) {
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? term
        if let url = URL(string: "dict://\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}
