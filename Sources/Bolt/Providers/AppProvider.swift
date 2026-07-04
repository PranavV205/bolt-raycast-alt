import AppKit

// Indexes installed applications (FR-5). Rescans lazily when stale.
final class AppProvider: SearchProvider {
    let name = "Apps"

    private struct AppEntry {
        let name: String
        let url: URL
    }

    private var entries: [AppEntry] = []
    private var lastScan: Date = .distantPast
    private var iconCache: [String: NSImage] = [:]
    private let scanQueue = DispatchQueue(label: "bolt.appscan", qos: .userInitiated)

    private let searchDirs = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
        "/System/Library/CoreServices/Applications",
    ]

    init() {
        scan()
    }

    func refreshIfStale() {
        guard Date().timeIntervalSince(lastScan) > 120 else { return }
        scanQueue.async { [weak self] in
            let found = Self.scanDirectories(self?.searchDirs ?? [])
            DispatchQueue.main.async {
                self?.entries = found
                self?.lastScan = Date()
            }
        }
    }

    private func scan() {
        entries = Self.scanDirectories(searchDirs)
        lastScan = Date()
    }

    private static func scanDirectories(_ dirs: [String]) -> [AppEntry] {
        let fm = FileManager.default
        var found: [String: AppEntry] = [:]  // dedupe by name, first dir wins

        for dir in dirs {
            guard let children = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for child in children {
                let path = dir + "/" + child
                if child.hasSuffix(".app") {
                    let name = String(child.dropLast(4))
                    if found[name] == nil {
                        found[name] = AppEntry(name: name, url: URL(fileURLWithPath: path))
                    }
                } else {
                    // One level of subfolders (e.g. /Applications/Adobe X).
                    guard let sub = try? fm.contentsOfDirectory(atPath: path) else { continue }
                    for inner in sub where inner.hasSuffix(".app") {
                        let name = String(inner.dropLast(4))
                        if found[name] == nil {
                            found[name] = AppEntry(name: name, url: URL(fileURLWithPath: path + "/" + inner))
                        }
                    }
                }
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func icon(for entry: AppEntry) -> NSImage {
        if let cached = iconCache[entry.url.path] { return cached }
        let img = NSWorkspace.shared.icon(forFile: entry.url.path)
        img.size = NSSize(width: 32, height: 32)
        iconCache[entry.url.path] = img
        return img
    }

    private func item(for entry: AppEntry, score: Double) -> ResultItem {
        ResultItem(
            id: "app:\(entry.url.path)",
            title: entry.name,
            subtitle: entry.url.deletingLastPathComponent().path,
            icon: .image(icon(for: entry)),
            kind: .app,
            score: score,
            action: { modifiers in
                if modifiers.contains(.command) {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                } else {
                    NSWorkspace.shared.openApplication(
                        at: entry.url,
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
                return .dismiss
            }
        )
    }

    func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        var items: [ResultItem] = []
        for entry in entries {
            if let s = FuzzyMatcher.score(query: query.lowercased, candidate: entry.name) {
                items.append(item(for: entry, score: s * 1.0))
            }
        }
        return items
    }

    // Empty-query default list: most-used apps first, then alphabetical.
    func defaultItems(limit: Int) -> [ResultItem] {
        let scored = entries.map { entry -> (AppEntry, Double) in
            (entry, Frecency.shared.boost(id: "app:\(entry.url.path)"))
        }
        let sorted = scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
        }
        return sorted.prefix(limit).map { item(for: $0.0, score: 1 + $0.1) }
    }
}
