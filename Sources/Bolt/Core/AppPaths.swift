import Foundation

// Central place for every file the app reads or writes.
// User-editable config lives in ~/.bolt, runtime state in
// ~/Library/Application Support/Bolt.
enum AppPaths {
    static let configDir: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bolt", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Bolt", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let clipboardImagesDir: URL = {
        let url = supportDir.appendingPathComponent("clipboard-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var configFile: URL { configDir.appendingPathComponent("config.json") }
    static var snippetsFile: URL { configDir.appendingPathComponent("snippets.json") }
    static var quicklinksFile: URL { configDir.appendingPathComponent("quicklinks.json") }

    static var frecencyFile: URL { supportDir.appendingPathComponent("frecency.json") }
    static var clipboardFile: URL { supportDir.appendingPathComponent("clipboard.json") }
    static var ratesFile: URL { supportDir.appendingPathComponent("rates.json") }
    static var scratchpadFile: URL { supportDir.appendingPathComponent("scratchpad.txt") }
}

// User-tweakable settings, loaded from ~/.bolt/config.json.
struct AppConfig: Codable {
    var clipboardHistoryEnabled: Bool = true
    var clipboardCapacity: Int = 50
    var snippetExpansionEnabled: Bool = true
    var fileSearchEnabled: Bool = true
    var maxResults: Int = 40
    var currencyEnabled: Bool = true

    static var shared: AppConfig = load()

    static func load() -> AppConfig {
        if let data = try? Data(contentsOf: AppPaths.configFile),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return cfg
        }
        let cfg = AppConfig()
        cfg.save()
        return cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: AppPaths.configFile)
        }
    }

    static func reload() { shared = load() }
}
