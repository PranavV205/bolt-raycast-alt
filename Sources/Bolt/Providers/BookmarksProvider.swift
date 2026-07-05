import AppKit

// Read-only browser bookmark search. Chromium-family browsers store one
// JSON file per profile; Safari a plist (readable only with Full Disk
// Access, so it is best-effort and silently skipped otherwise). Loaded off
// the main thread, refreshed at most every five minutes.
final class BookmarksProvider: SearchProvider {
    let name = "Bookmarks"

    private struct Bookmark {
        let title: String
        let url: String
        let host: String
    }

    private var bookmarks: [Bookmark] = []
    private var loadedAt = Date.distantPast
    private var loading = false

    init() {
        refreshIfStale()
    }

    func refreshIfStale() {
        guard AppConfig.shared.bookmarksEnabled else {
            bookmarks = []
            return
        }
        guard Date().timeIntervalSince(loadedAt) > 300, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let loaded = Self.loadAll()
            DispatchQueue.main.async {
                self?.bookmarks = loaded
                self?.loadedAt = Date()
                self?.loading = false
            }
        }
    }

    func results(for query: Query) -> [ResultItem] {
        guard AppConfig.shared.bookmarksEnabled, query.trimmed.count >= 2 else { return [] }
        var items: [ResultItem] = []

        for bookmark in bookmarks {
            // Match title and host only; fuzzy over full URLs is pure noise.
            guard let score = FuzzyMatcher.score(query: query.lowercased, fields: [bookmark.title, bookmark.host]) else { continue }
            let url = bookmark.url
            items.append(ResultItem(
                id: "bookmark:\(url)",
                title: bookmark.title,
                subtitle: url.count > 90 ? String(url.prefix(90)) + "..." : url,
                icon: .symbol("bookmark.fill"),
                kind: .bookmark,
                score: score * 0.7,   // below apps and commands at equal match
                action: { _ in
                    if let target = URL(string: url) { NSWorkspace.shared.open(target) }
                    return .dismiss
                }
            ))
        }
        return items
    }

    // MARK: - Loading

    private static func loadAll() -> [Bookmark] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var all: [Bookmark] = []

        let chromiumRoots = [
            "Library/Application Support/Google/Chrome",
            "Library/Application Support/BraveSoftware/Brave-Browser",
            "Library/Application Support/Microsoft Edge",
            "Library/Application Support/Chromium",
            "Library/Application Support/Vivaldi",
        ]
        for root in chromiumRoots {
            let dir = home.appendingPathComponent(root)
            guard let profiles = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for profile in profiles where profile == "Default" || profile.hasPrefix("Profile ") {
                all += parseChromium(dir.appendingPathComponent(profile).appendingPathComponent("Bookmarks"))
            }
        }

        all += parseSafari(home.appendingPathComponent("Library/Safari/Bookmarks.plist"))

        // Same page bookmarked in several browsers/profiles: keep one.
        var seen = Set<String>()
        var deduped: [Bookmark] = []
        for bookmark in all where seen.insert(bookmark.url).inserted {
            deduped.append(bookmark)
        }
        return deduped
    }

    private static func make(title: String, url: String) -> Bookmark? {
        guard url.hasPrefix("http") else { return nil }   // skip javascript:, chrome:, file:
        let host = URL(string: url)?.host ?? ""
        return Bookmark(title: title.isEmpty ? host : title, url: url, host: host)
    }

    private static func parseChromium(_ file: URL) -> [Bookmark] {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return [] }

        var out: [Bookmark] = []
        func walk(_ node: [String: Any]) {
            if node["type"] as? String == "url",
               let name = node["name"] as? String,
               let url = node["url"] as? String,
               let bookmark = make(title: name, url: url) {
                out.append(bookmark)
            }
            for child in node["children"] as? [[String: Any]] ?? [] {
                walk(child)
            }
        }
        for (_, root) in roots {
            if let dict = root as? [String: Any] { walk(dict) }
        }
        return out
    }

    private static func parseSafari(_ file: URL) -> [Bookmark] {
        guard let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }

        var out: [Bookmark] = []
        func walk(_ node: [String: Any]) {
            if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf",
               let url = node["URLString"] as? String {
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""
                if let bookmark = make(title: title, url: url) {
                    out.append(bookmark)
                }
            }
            for child in node["Children"] as? [[String: Any]] ?? [] {
                walk(child)
            }
        }
        walk(plist)
        return out
    }
}
