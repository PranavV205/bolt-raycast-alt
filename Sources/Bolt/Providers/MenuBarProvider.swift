import AppKit

// Fuzzy-search every menu item of the app you were in ("/" prefix).
// The menu tree is walked in the background when the panel opens, so
// results are instant while typing.
final class MenuBarProvider {

    struct MenuEntry {
        let title: String
        let path: String
        let element: AXUIElement
    }

    private var cache: [MenuEntry] = []
    private var appName = ""
    private var loading = false
    private var fetchGeneration = 0

    func prefetch(app: NSRunningApplication?) {
        cache = []
        guard AX.trusted,
              let app,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        appName = app.localizedName ?? "frontmost app"
        loading = true
        fetchGeneration += 1
        let gen = fetchGeneration
        let pid = app.processIdentifier

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = Self.walkMenuBar(pid: pid)
            DispatchQueue.main.async {
                guard let self, gen == self.fetchGeneration else { return }
                self.cache = entries
                self.loading = false
            }
        }
    }

    func search(_ term: String) -> [ResultItem] {
        guard AX.trusted else {
            return [infoItem(
                "Grant Accessibility access to search menus",
                subtitle: "System Settings > Privacy & Security > Accessibility"
            )]
        }
        if cache.isEmpty {
            return [infoItem(
                loading ? "Reading \(appName) menus..." : "No menu items found for \(appName)",
                subtitle: "Menu search targets the app you were in"
            )]
        }

        var items: [ResultItem] = []
        for entry in cache {
            let score: Double
            if term.isEmpty {
                score = 0.5
            } else if let s = FuzzyMatcher.score(query: term, fields: [entry.title, entry.path]) {
                score = s
            } else {
                continue
            }
            let element = entry.element
            items.append(ResultItem(
                id: "menu:\(appName):\(entry.path)",
                title: entry.title,
                subtitle: "\(appName)  ·  \(entry.path)",
                icon: .symbol("filemenu.and.selection"),
                kind: .menuItem,
                score: score,
                action: { _ in
                    AX.press(element)
                    return .dismiss
                }
            ))
        }
        items.sort { $0.score > $1.score }
        return Array(items.prefix(30))
    }

    private func infoItem(_ title: String, subtitle: String) -> ResultItem {
        ResultItem(
            id: "menu:info",
            title: title,
            subtitle: subtitle,
            icon: .symbol("filemenu.and.selection"),
            kind: .menuItem,
            score: 0.1,
            action: { _ in .dismiss }
        )
    }

    // MARK: AX walking

    private static func walkMenuBar(pid: pid_t) -> [MenuEntry] {
        let axApp = AXUIElementCreateApplication(pid)
        guard let ref = AX.attribute(axApp, kAXMenuBarAttribute as String) else { return [] }
        let menuBar = ref as! AXUIElement

        var entries: [MenuEntry] = []
        var count = 0
        let topLevel = AX.children(menuBar)

        for (index, barItem) in topLevel.enumerated() {
            if index == 0 { continue } // skip the Apple menu
            let title = AX.string(barItem, kAXTitleAttribute as String) ?? ""
            guard !title.isEmpty else { continue }
            walk(element: barItem, path: title, depth: 0, entries: &entries, count: &count)
        }
        return entries
    }

    private static func walk(
        element: AXUIElement, path: String, depth: Int,
        entries: inout [MenuEntry], count: inout Int
    ) {
        guard depth < 6, count < 900 else { return }

        for child in AX.children(element) {
            guard count < 900 else { return }
            let role = AX.string(child, kAXRoleAttribute as String) ?? ""

            if role == "AXMenu" {
                // Container: descend without extending the path.
                walk(element: child, path: path, depth: depth + 1, entries: &entries, count: &count)
                continue
            }

            guard role == "AXMenuItem" else { continue }
            let title = AX.string(child, kAXTitleAttribute as String) ?? ""
            if title.isEmpty { continue } // separator

            let subMenus = AX.children(child)
            if subMenus.isEmpty {
                if AX.bool(child, kAXEnabledAttribute as String) ?? true {
                    entries.append(MenuEntry(title: title, path: path, element: child))
                    count += 1
                }
            } else {
                walk(element: child, path: path + " > " + title, depth: depth + 1, entries: &entries, count: &count)
            }
        }
    }
}
