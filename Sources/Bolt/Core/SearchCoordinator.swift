import AppKit
import Combine

// Owns the query, fans it out to providers, ranks the merged results.
final class SearchCoordinator: ObservableObject {
    @Published private(set) var results: [ResultItem] = []
    @Published var selectedIndex: Int = 0
    @Published var armedConfirmationId: String?

    weak var textField: NSTextField?
    var onOutcome: ((ActionOutcome) -> Void)?

    private(set) var query: String = ""
    private var generation = 0

    // Providers
    let appProvider = AppProvider()
    let fileProvider = FileProvider()
    let calculatorProvider = CalculatorProvider()
    let conversionProvider = ConversionProvider()
    let clipboardProvider = ClipboardProvider()
    let snippetsProvider = SnippetsProvider()
    let quicklinksProvider = QuicklinksProvider()
    let systemProvider = SystemCommandProvider()
    let processProvider = ProcessProvider()
    let emojiProvider = EmojiProvider()
    let windowSwitcher = WindowSwitcherProvider()
    let menuBarProvider = MenuBarProvider()
    let dictionaryProvider = DictionaryProvider()
    let windowCommands = WindowCommandProvider()
    let featureCommands = FeatureCommandProvider()
    let bookmarksProvider = BookmarksProvider()

    // Providers consulted for a plain (non-prefixed) query.
    private var generalProviders: [SearchProvider] {
        [
            calculatorProvider,
            conversionProvider,
            appProvider,
            windowSwitcher,
            snippetsProvider,
            quicklinksProvider,
            bookmarksProvider,
            systemProvider,
            windowCommands,
            featureCommands,
        ]
    }

    // Called by the panel each time it is summoned.
    func prepareForOpen(targetApp: NSRunningApplication?) {
        appProvider.refreshIfStale()
        bookmarksProvider.refreshIfStale()
        windowSwitcher.prefetch()
        menuBarProvider.prefetch(app: targetApp)
        CurrencyService.shared.refreshIfStale()
        setQuery("")
    }

    func setQuery(_ text: String) {
        textField?.stringValue = text
        queryDidChange(text)
        // Keep the insertion point at the end after programmatic changes.
        if let tf = textField, let editor = tf.currentEditor() {
            editor.selectedRange = NSRange(location: text.count, length: 0)
        }
    }

    func queryDidChange(_ text: String) {
        query = text
        generation += 1
        armedConfirmationId = nil
        compute()
    }

    private func compute() {
        let q = Query(AliasStore.shared.rewrite(query))
        let gen = generation

        if q.isEmpty {
            results = defaultResults()
            selectedIndex = 0
            return
        }

        var items: [ResultItem]

        if q.trimmed.hasPrefix("/") {
            let arg = String(q.trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            items = menuBarProvider.search(arg)
        } else if q.trimmed.hasPrefix(":") {
            items = emojiProvider.search(String(q.trimmed.dropFirst()))
        } else if let arg = q.argument(afterKeyword: "clip") ?? q.argument(afterKeyword: "clipboard") {
            items = clipboardProvider.search(arg)
        } else if let arg = q.argument(afterKeyword: "kill"), !arg.isEmpty || q.lowercased == "kill" {
            if let port = ProcessProvider.portNumber(in: arg) {
                items = processProvider.portItems(port: port, onRefresh: refreshIfCurrent(gen))
            } else {
                items = processProvider.search(arg)
            }
        } else if let arg = q.argument(afterKeyword: "servers") ?? q.argument(afterKeyword: "ports"),
                  !arg.isEmpty || q.lowercased == "servers" || q.lowercased == "ports" {
            items = processProvider.serverItems(filter: arg, onRefresh: refreshIfCurrent(gen))
        } else if let arg = q.argument(afterKeyword: "define"), !arg.isEmpty {
            items = dictionaryProvider.define(arg)
        } else if let arg = q.argument(afterKeyword: "emoji") {
            items = emojiProvider.search(arg)
        } else {
            items = []
            for provider in generalProviders {
                items.append(contentsOf: provider.results(for: q))
            }
            applyFrecency(&items)
            // Kick off the async file search and merge when it lands.
            if AppConfig.shared.fileSearchEnabled, q.trimmed.count >= 3 {
                fileProvider.search(query: q) { [weak self] fileItems in
                    self?.mergeAsync(fileItems, generation: gen)
                }
            }
        }

        items.sort { $0.score > $1.score }
        results = Array(items.prefix(AppConfig.shared.maxResults))
        selectedIndex = 0
    }

    // Re-runs compute once a background scan lands, unless the query moved on.
    private func refreshIfCurrent(_ gen: Int) -> () -> Void {
        { [weak self] in
            guard let self, self.generation == gen else { return }
            self.compute()
        }
    }

    private func applyFrecency(_ items: inout [ResultItem]) {
        for i in items.indices {
            items[i].score *= 1.0 + Frecency.shared.boost(id: items[i].id)
        }
    }

    private func mergeAsync(_ newItems: [ResultItem], generation gen: Int) {
        guard gen == generation, !newItems.isEmpty else { return }
        let selectedId = results.indices.contains(selectedIndex) ? results[selectedIndex].id : nil
        var merged = results
        let existing = Set(merged.map(\.id))
        merged.append(contentsOf: newItems.filter { !existing.contains($0.id) })
        merged.sort { $0.score > $1.score }
        results = Array(merged.prefix(AppConfig.shared.maxResults))
        if let sid = selectedId, let idx = results.firstIndex(where: { $0.id == sid }) {
            selectedIndex = idx
        } else {
            selectedIndex = 0
        }
    }

    // Empty query: most-used apps, so the panel is never blank.
    private func defaultResults() -> [ResultItem] {
        appProvider.defaultItems(limit: 9)
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    func executeSelected(modifiers: NSEvent.ModifierFlags) {
        guard results.indices.contains(selectedIndex) else { return }
        let item = results[selectedIndex]

        if item.needsConfirmation && armedConfirmationId != item.id {
            armedConfirmationId = item.id
            return
        }
        armedConfirmationId = nil
        Frecency.shared.recordUse(id: item.id)
        let outcome = item.action(modifiers)
        onOutcome?(outcome)
    }

    func execute(at index: Int, modifiers: NSEvent.ModifierFlags) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
        executeSelected(modifiers: modifiers)
    }
}
