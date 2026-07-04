import AppKit

// Emoji picker: ":fire" or "emoji rocket". Enter pastes the emoji into
// the previous app, Cmd+Enter just copies it.
final class EmojiProvider {

    func search(_ term: String) -> [ResultItem] {
        let entries = EmojiData.all
        var items: [ResultItem] = []

        for entry in entries {
            let score: Double
            if term.isEmpty {
                score = 0.5
            } else if let s = FuzzyMatcher.score(query: term.lowercased(), candidate: entry.name) {
                score = s
            } else {
                continue
            }

            items.append(ResultItem(
                id: "emoji:\(entry.char)",
                title: entry.name.capitalized,
                subtitle: nil,
                icon: .emoji(entry.char),
                kind: .emojiItem,
                score: score,
                accessory: entry.char,
                action: { modifiers in
                    ClipboardManager.shared.ignoreNextChange = true
                    if modifiers.contains(.command) {
                        PasteHelper.copy(text: entry.char)
                        return .toast("Copied \(entry.char)")
                    }
                    if PasteHelper.paste(text: entry.char) {
                        return .dismiss
                    }
                    return .toast("Copied \(entry.char)")
                }
            ))
        }

        items.sort { $0.score > $1.score }
        return Array(items.prefix(30))
    }
}
