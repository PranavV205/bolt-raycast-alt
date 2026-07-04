import AppKit

// Surfaces clipboard history under the "clip" / "clipboard" keyword and
// the dedicated Ctrl+Option+V hotkey. Enter pastes into the previous app,
// Cmd+Enter only copies, Ctrl+Enter deletes the entry.
final class ClipboardProvider {

    private let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    func search(_ term: String) -> [ResultItem] {
        let manager = ClipboardManager.shared
        var results: [ResultItem] = []

        for (index, item) in manager.items.enumerated() {
            let title: String
            let icon: ResultIcon
            var matchScore: Double = 1.0 - Double(index) * 0.01  // recent first

            switch item.content {
            case .text(let text):
                let collapsed = text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                title = String(collapsed.prefix(90))
                icon = .symbol("doc.on.clipboard")
                if !term.isEmpty {
                    // Substring match is what you want in clipboard search,
                    // fall back to fuzzy for looser recall.
                    if collapsed.lowercased().contains(term.lowercased()) {
                        matchScore += 1.0
                    } else if let fuzzy = FuzzyMatcher.score(query: term, candidate: String(collapsed.prefix(200))) {
                        matchScore += fuzzy * 0.5
                    } else {
                        continue
                    }
                }
            case .imageFile:
                title = "Image"
                if let img = ClipboardManager.shared.image(for: item) {
                    icon = .image(img)
                } else {
                    icon = .symbol("photo")
                }
                if !term.isEmpty, FuzzyMatcher.score(query: term, candidate: "image") == nil {
                    continue
                }
            }

            var subtitleParts: [String] = [dateFormatter.localizedString(for: item.date, relativeTo: Date())]
            if let app = item.sourceApp { subtitleParts.append("from \(app)") }

            results.append(ResultItem(
                id: "clip:\(item.id)",
                title: title.isEmpty ? "(whitespace)" : title,
                subtitle: subtitleParts.joined(separator: "  ·  "),
                icon: icon,
                kind: .clipboard,
                score: matchScore,
                accessory: index == 0 ? "latest" : nil,
                action: { modifiers in
                    Self.perform(item: item, modifiers: modifiers)
                }
            ))
        }

        if results.isEmpty {
            results.append(ResultItem(
                id: "clip:empty",
                title: term.isEmpty ? "Clipboard history is empty" : "No clips match \"\(term)\"",
                subtitle: "Copy something and it will show up here",
                icon: .symbol("doc.on.clipboard"),
                kind: .clipboard,
                score: 0.1,
                action: { _ in .dismiss }
            ))
        }
        return results
    }

    private static func perform(item: ClipboardManager.Item, modifiers: NSEvent.ModifierFlags) -> ActionOutcome {
        if modifiers.contains(.control) {
            ClipboardManager.shared.delete(id: item.id)
            return .replaceQuery("clip ")
        }

        ClipboardManager.shared.ignoreNextChange = true

        switch item.content {
        case .text(let text):
            if modifiers.contains(.command) {
                PasteHelper.copy(text: text)
                return .toast("Copied")
            }
            if PasteHelper.paste(text: text) {
                return .dismiss
            }
            return .toast("Copied (grant Accessibility to auto-paste)")
        case .imageFile:
            guard let image = ClipboardManager.shared.image(for: item) else {
                return .toast("Image file missing")
            }
            if modifiers.contains(.command) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
                return .toast("Copied")
            }
            if PasteHelper.paste(image: image) {
                return .dismiss
            }
            return .toast("Copied (grant Accessibility to auto-paste)")
        }
    }
}
