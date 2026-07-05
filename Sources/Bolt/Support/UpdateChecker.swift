import AppKit

// Once-a-day check against the GitHub releases API, mirroring the
// CurrencyService pattern: tiny JSON fetch, state cached on disk, silent
// unless there is something to say. Disable with "updateCheckEnabled": false.
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let releasesPage = URL(string: "https://github.com/PranavV205/bolt-raycast-alt/releases/latest")!
    private let apiURL = URL(string: "https://api.github.com/repos/PranavV205/bolt-raycast-alt/releases/latest")!
    private let stateFile = AppPaths.supportDir.appendingPathComponent("update-check.json")

    // Set when a newer release is known; FeatureCommandProvider surfaces it.
    private(set) var availableVersion: String?

    private struct State: Codable {
        var lastCheck: Date
        var lastNotified: String?
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkIfStale() {
        guard AppConfig.shared.updateCheckEnabled else { return }
        if let state = loadState(), Date().timeIntervalSince(state.lastCheck) < 24 * 60 * 60 {
            return
        }
        check(manual: false)
    }

    // manual: invoked from the "Check for Updates" command; always reports.
    func check(manual: Bool) {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            let tag = data.flatMap {
                try? JSONDecoder().decode(Release.self, from: $0)
            }?.tagName
            DispatchQueue.main.async { self.handle(tag: tag, manual: manual) }
        }.resume()
    }

    private struct Release: Codable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }

    private func handle(tag: String?, manual: Bool) {
        guard let tag else {
            if manual { Toast.show("Update check failed", symbol: "wifi.exclamationmark") }
            return
        }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        var state = loadState() ?? State(lastCheck: Date())
        state.lastCheck = Date()

        if Self.isNewer(latest, than: Self.currentVersion) {
            availableVersion = latest
            // Auto-checks nag once per version; manual checks always answer.
            if manual || state.lastNotified != latest {
                state.lastNotified = latest
                Toast.show(
                    "Bolt \(latest) is available, click to download",
                    symbol: "arrow.down.circle.fill",
                    duration: 6,
                    action: { NSWorkspace.shared.open(Self.releasesPage) }
                )
            }
        } else if manual {
            Toast.show("Bolt \(Self.currentVersion) is up to date")
        }
        saveState(state)
    }

    // Numeric semver comparison; unequal lengths pad with zeros.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func loadState() -> State? {
        guard let data = try? Data(contentsOf: stateFile) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func saveState(_ state: State) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFile)
        }
    }
}
