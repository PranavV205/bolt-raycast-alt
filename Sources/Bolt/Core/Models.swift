import AppKit

// What happens after a result's action runs.
enum ActionOutcome {
    case dismiss                 // close the launcher
    case toast(String)           // close and show a small confirmation
    case stay                    // keep the launcher open (e.g. confirmation armed)
    case replaceQuery(String)    // keep open, replace the search text
}

enum ResultIcon {
    case image(NSImage)
    case symbol(String)          // SF Symbol name
    case emoji(String)
    case none
}

enum ResultKind: String {
    case app = "App"
    case window = "Window"
    case file = "File"
    case command = "Command"
    case calculator = "Calc"
    case conversion = "Convert"
    case clipboard = "Clipboard"
    case snippet = "Snippet"
    case quicklink = "Link"
    case emojiItem = "Emoji"
    case system = "System"
    case process = "Process"
    case menuItem = "Menu"
    case definition = "Define"
    case color = "Color"
}

struct ResultItem: Identifiable {
    let id: String               // stable across sessions, used for frecency
    let title: String
    var subtitle: String?
    let icon: ResultIcon
    let kind: ResultKind
    var score: Double            // relevance before frecency boost
    var accessory: String?       // right-aligned text (calc result, hotkey hint)
    var needsConfirmation: Bool = false
    // Receives the keyboard modifiers held when Enter was pressed.
    let action: (NSEvent.ModifierFlags) -> ActionOutcome
}

// Parsed query passed to providers.
struct Query {
    let raw: String
    let trimmed: String
    let lowercased: String

    init(_ raw: String) {
        self.raw = raw
        self.trimmed = raw.trimmingCharacters(in: .whitespaces)
        self.lowercased = trimmed.lowercased()
    }

    var isEmpty: Bool { trimmed.isEmpty }

    // "kill chro" -> ("kill", "chro") when matched against a prefix keyword.
    func argument(afterKeyword keyword: String) -> String? {
        guard lowercased == keyword || lowercased.hasPrefix(keyword + " ") else { return nil }
        if lowercased == keyword { return "" }
        return String(trimmed.dropFirst(keyword.count + 1)).trimmingCharacters(in: .whitespaces)
    }
}

// Providers that answer synchronously from in-memory data.
protocol SearchProvider {
    var name: String { get }
    func results(for query: Query) -> [ResultItem]
}
