import Foundation

// Per-command aliases from ~/.bolt/aliases.json: a flat map of keyword to
// the query it stands for. Typing "dm" searches as if you typed "dark mode".
// The alias must be the first word; anything after it is appended, so an
// alias can front a quicklink that takes arguments.
final class AliasStore {
    static let shared = AliasStore()

    private(set) var aliases: [String: String] = [:]

    private init() {
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: AppPaths.aliasesFile),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            aliases = Dictionary(uniqueKeysWithValues: decoded.map { ($0.key.lowercased(), $0.value) })
            return
        }
        // First run: write a starter file the user can edit.
        aliases = ["dm": "dark mode"]
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(aliases) {
            try? data.write(to: AppPaths.aliasesFile)
        }
    }

    func rewrite(_ text: String) -> String {
        Self.rewrite(text, aliases: aliases)
    }

    // Rewrites a query whose first word is an alias. Case-insensitive on
    // the keyword, leaves everything else untouched.
    static func rewrite(_ text: String, aliases: [String: String]) -> String {
        guard !aliases.isEmpty else { return text }
        let trimmedLeading = text.drop(while: { $0 == " " })
        guard !trimmedLeading.isEmpty else { return text }

        let firstWord: Substring
        let rest: Substring
        if let space = trimmedLeading.firstIndex(of: " ") {
            firstWord = trimmedLeading[..<space]
            rest = trimmedLeading[space...]
        } else {
            firstWord = trimmedLeading
            rest = ""
        }

        guard let expansion = aliases[firstWord.lowercased()] else { return text }
        return expansion + rest
    }
}
