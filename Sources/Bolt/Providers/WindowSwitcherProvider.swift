import AppKit

// Jump to a specific open window of any running app, not just launch the
// app. Enumerated via Accessibility on panel open, cached for the session
// of that summon.
final class WindowSwitcherProvider: SearchProvider {
    let name = "Windows"

    private struct WindowEntry {
        let appName: String
        let title: String
        let pid: pid_t
        let element: AXUIElement
        let icon: NSImage?
    }

    private var cache: [WindowEntry] = []
    private var fetchGeneration = 0

    func prefetch() {
        guard AX.trusted else { return }
        fetchGeneration += 1
        let gen = fetchGeneration
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            !$0.isTerminated &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let appInfo = apps.map { ($0.processIdentifier, $0.localizedName ?? "App", $0.icon) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var entries: [WindowEntry] = []
            for (pid, name, icon) in appInfo {
                let axApp = AXUIElementCreateApplication(pid)
                guard let ref = AX.attribute(axApp, kAXWindowsAttribute as String),
                      let windows = ref as? [AnyObject] else { continue }
                for w in windows.prefix(20) {
                    let window = w as! AXUIElement
                    let title = AX.string(window, kAXTitleAttribute as String) ?? ""
                    guard !title.isEmpty else { continue }
                    entries.append(WindowEntry(
                        appName: name, title: title, pid: pid, element: window, icon: icon
                    ))
                }
            }
            DispatchQueue.main.async {
                guard let self, gen == self.fetchGeneration else { return }
                self.cache = entries
            }
        }
    }

    func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        var items: [ResultItem] = []

        for entry in cache {
            guard let score = FuzzyMatcher.score(
                query: query.lowercased,
                fields: [entry.title, "\(entry.appName) \(entry.title)"]
            ) else { continue }

            let icon: ResultIcon
            if let img = entry.icon {
                icon = .image(img)
            } else {
                icon = .symbol("macwindow")
            }

            let element = entry.element
            let pid = entry.pid
            items.append(ResultItem(
                id: "win:\(entry.pid):\(entry.title)",
                title: entry.title,
                subtitle: "\(entry.appName) window",
                icon: icon,
                kind: .window,
                score: score * 0.9,
                action: { _ in
                    // Unminimize if needed, raise, then bring the app forward.
                    if AX.bool(element, kAXMinimizedAttribute as String) == true {
                        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    }
                    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
                    return .dismiss
                }
            ))
        }
        return items
    }
}
