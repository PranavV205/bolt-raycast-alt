import AppKit

struct Quicklink: Codable {
    var keyword: String    // "gh"
    var name: String       // "GitHub"
    var template: String   // "https://github.com/search?q={query}"
    var base: String?      // opened when no argument is given
}

// Parameterized URL shortcuts: "gh swift-argument-parser", "g fastapi docs".
// Editable at ~/.bolt/quicklinks.json, hot-reloaded via "reload".
final class QuicklinksProvider: SearchProvider {
    let name = "Quicklinks"

    private(set) var links: [Quicklink] = []

    init() {
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: AppPaths.quicklinksFile),
           let decoded = try? JSONDecoder().decode([Quicklink].self, from: data) {
            links = decoded
            return
        }
        links = [
            Quicklink(keyword: "g", name: "Google", template: "https://www.google.com/search?q={query}", base: "https://www.google.com"),
            Quicklink(keyword: "gh", name: "GitHub", template: "https://github.com/search?q={query}", base: "https://github.com"),
            Quicklink(keyword: "yt", name: "YouTube", template: "https://www.youtube.com/results?search_query={query}", base: "https://www.youtube.com"),
            Quicklink(keyword: "npm", name: "npm", template: "https://www.npmjs.com/search?q={query}", base: "https://www.npmjs.com"),
            Quicklink(keyword: "pypi", name: "PyPI", template: "https://pypi.org/search/?q={query}", base: "https://pypi.org"),
            Quicklink(keyword: "wiki", name: "Wikipedia", template: "https://en.wikipedia.org/w/index.php?search={query}", base: "https://en.wikipedia.org"),
            Quicklink(keyword: "mdn", name: "MDN", template: "https://developer.mozilla.org/en-US/search?q={query}", base: "https://developer.mozilla.org"),
            Quicklink(keyword: "maps", name: "Google Maps", template: "https://www.google.com/maps/search/{query}", base: "https://www.google.com/maps"),
            Quicklink(keyword: "tr", name: "Google Translate", template: "https://translate.google.com/?text={query}", base: "https://translate.google.com"),
        ]
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(links) {
            try? data.write(to: AppPaths.quicklinksFile)
        }
    }

    func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        var items: [ResultItem] = []
        let words = query.trimmed.split(separator: " ", maxSplits: 1)
        let firstWord = words.first.map(String.init)?.lowercased() ?? ""
        let argument = words.count > 1 ? String(words[1]) : ""

        for link in links {
            if link.keyword == firstWord {
                // Exact keyword: pinned near the top with the argument wired in.
                let title = argument.isEmpty
                    ? "Open \(link.name)"
                    : "Search \(link.name) for \"\(argument)\""
                items.append(item(link: link, argument: argument, title: title, score: 2.2))
            } else if argument.isEmpty,
                      let s = FuzzyMatcher.score(query: query.lowercased, fields: [link.name, link.keyword]) {
                items.append(item(link: link, argument: "", title: "Open \(link.name)", score: s * 0.75))
            }
        }
        return items
    }

    private func item(link: Quicklink, argument: String, title: String, score: Double) -> ResultItem {
        ResultItem(
            id: "quicklink:\(link.keyword)",
            title: title,
            subtitle: resolvedURL(link: link, argument: argument)?.absoluteString ?? link.template,
            icon: .symbol("link.circle.fill"),
            kind: .quicklink,
            score: score,
            accessory: link.keyword,
            action: { _ in
                guard let url = Self.staticResolve(link: link, argument: argument) else {
                    return .toast("Bad quicklink URL")
                }
                NSWorkspace.shared.open(url)
                return .dismiss
            }
        )
    }

    private func resolvedURL(link: Quicklink, argument: String) -> URL? {
        Self.staticResolve(link: link, argument: argument)
    }

    private static func staticResolve(link: Quicklink, argument: String) -> URL? {
        if argument.isEmpty {
            return URL(string: link.base ?? link.template.replacingOccurrences(of: "{query}", with: ""))
        }
        let encoded = argument.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? argument
        return URL(string: link.template.replacingOccurrences(of: "{query}", with: encoded))
    }
}
