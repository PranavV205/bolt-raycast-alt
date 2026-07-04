import AppKit

struct Snippet: Codable {
    var keyword: String   // typed trigger, e.g. ";sig"
    var name: String
    var content: String

    // Supported placeholders inside content.
    func expandedContent() -> String {
        var text = content
        if text.contains("{date}") {
            let f = DateFormatter()
            f.dateStyle = .medium
            text = text.replacingOccurrences(of: "{date}", with: f.string(from: Date()))
        }
        if text.contains("{time}") {
            let f = DateFormatter()
            f.timeStyle = .short
            text = text.replacingOccurrences(of: "{time}", with: f.string(from: Date()))
        }
        if text.contains("{clipboard}") {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            text = text.replacingOccurrences(of: "{clipboard}", with: clip)
        }
        return text
    }
}

// Loads ~/.bolt/snippets.json and serves snippets in search results.
// Live ";keyword" expansion while typing anywhere is SnippetExpander's job.
final class SnippetsProvider: SearchProvider {
    let name = "Snippets"

    private(set) var snippets: [Snippet] = []

    init() {
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: AppPaths.snippetsFile),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = decoded
            return
        }
        // First run: write a starter file the user can edit.
        snippets = [
            Snippet(
                keyword: ";sig",
                name: "Email signature",
                content: "Best,\nYour Name"
            ),
            Snippet(
                keyword: ";date",
                name: "Today's date",
                content: "{date}"
            ),
            Snippet(
                keyword: ";shrug",
                name: "Shrug",
                content: "¯\\_(ツ)_/¯"
            ),
        ]
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(snippets) {
            try? data.write(to: AppPaths.snippetsFile)
        }
    }

    func reload() {
        load()
        SnippetExpander.shared.update(snippets: snippets)
    }

    func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        var items: [ResultItem] = []

        for snippet in snippets {
            guard let score = FuzzyMatcher.score(
                query: query.lowercased,
                fields: [snippet.name, snippet.keyword, "snippet " + snippet.name]
            ) else { continue }

            let preview = snippet.content
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(60)

            items.append(ResultItem(
                id: "snippet:\(snippet.keyword)",
                title: snippet.name,
                subtitle: String(preview),
                icon: .symbol("text.badge.plus"),
                kind: .snippet,
                score: score * 0.9,
                accessory: snippet.keyword,
                action: { modifiers in
                    let content = snippet.expandedContent()
                    ClipboardManager.shared.ignoreNextChange = true
                    if modifiers.contains(.command) {
                        PasteHelper.copy(text: content)
                        return .toast("Snippet copied")
                    }
                    if PasteHelper.paste(text: content) {
                        return .dismiss
                    }
                    return .toast("Copied (grant Accessibility to auto-paste)")
                }
            ))
        }
        return items
    }
}
