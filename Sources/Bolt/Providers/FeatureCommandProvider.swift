import AppKit
import ServiceManagement

// Launcher-owned commands: color picker, scratchpad, clipboard shortcut,
// config management, launch at login, quit. Also converts typed hex
// colors ("#ff8800") inline.
final class FeatureCommandProvider: SearchProvider {
    let name = "Features"

    func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        var items: [ResultItem] = []

        // Typed hex color: show conversions as the top result.
        if let color = ColorTools.parseHex(query.trimmed) {
            let hex = ColorTools.hexString(color)
            let rgb = ColorTools.rgbString(color)
            let hsl = ColorTools.hslString(color)
            items.append(ResultItem(
                id: "color:hex",
                title: "\(hex)  ·  \(rgb)  ·  \(hsl)",
                subtitle: "Color conversion, Enter copies rgb()",
                icon: .symbol("paintpalette.fill"),
                kind: .color,
                score: 3.0,
                accessory: "⏎ copies",
                action: { _ in
                    ClipboardManager.shared.ignoreNextChange = true
                    PasteHelper.copy(text: rgb)
                    return .toast("Copied \(rgb)")
                }
            ))
        }

        let statics: [(id: String, title: String, subtitle: String, symbol: String, aliases: [String], run: () -> ActionOutcome)] = [
            (
                "feature:pickcolor", "Pick Color", "Screen eyedropper, copies hex",
                "eyedropper.halffull", ["color picker", "eyedropper", "colour"],
                {
                    ColorTools.pickColor()
                    return .dismiss
                }
            ),
            (
                "feature:scratchpad", "Scratchpad", "Floating quick note (Ctrl+Option+S)",
                "note.text", ["note", "notes", "jot", "quick note"],
                {
                    Scratchpad.shared.toggle()
                    return .dismiss
                }
            ),
            (
                "feature:clipboard", "Clipboard History", "Browse and paste recent clips (Ctrl+Option+V)",
                "doc.on.clipboard.fill", ["clips", "paste history", "history"],
                { .replaceQuery("clip ") }
            ),
            (
                "feature:emoji", "Emoji Picker", "Search and paste emoji (or type :name)",
                "face.smiling", ["emojis", "smiley"],
                { .replaceQuery(":") }
            ),
            (
                "feature:menusearch", "Search Menu Items", "Menus of the app you were in (or type /)",
                "filemenu.and.selection", ["menu", "menubar", "menu bar"],
                { .replaceQuery("/") }
            ),
            (
                "feature:config", "Open Bolt Config Folder", "snippets.json, quicklinks.json, config.json",
                "folder.fill.badge.gearshape", ["settings", "preferences", "configure"],
                {
                    NSWorkspace.shared.open(AppPaths.configDir)
                    return .dismiss
                }
            ),
            (
                "feature:reload", "Reload Bolt Config", "Re-read snippets, quicklinks and settings",
                "arrow.clockwise.circle.fill", ["refresh config", "reload snippets"],
                {
                    AppConfig.reload()
                    NotificationCenter.default.post(name: .boltReloadConfig, object: nil)
                    return .toast("Config reloaded")
                }
            ),
            (
                "feature:loginitem", "Toggle Launch at Login", "Start Bolt when you log in",
                "power", ["login item", "startup", "autostart"],
                { Self.toggleLoginItem() }
            ),
            (
                "feature:quit", "Quit Bolt", "Stop the launcher agent",
                "xmark.octagon.fill", ["exit bolt"],
                {
                    NSApp.terminate(nil)
                    return .dismiss
                }
            ),
        ]

        for cmd in statics {
            guard let score = FuzzyMatcher.score(query: query.lowercased, fields: [cmd.title] + cmd.aliases) else { continue }
            items.append(ResultItem(
                id: cmd.id,
                title: cmd.title,
                subtitle: cmd.subtitle,
                icon: .symbol(cmd.symbol),
                kind: .command,
                score: score * 0.8,
                action: { _ in cmd.run() }
            ))
        }
        return items
    }

    private static func toggleLoginItem() -> ActionOutcome {
        // SMAppService only works from a real .app bundle.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return .toast("Run from Bolt.app to manage login item")
        }
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled {
                try service.unregister()
                return .toast("Launch at login disabled")
            } else {
                try service.register()
                return .toast("Launch at login enabled")
            }
        } catch {
            return .toast("Login item change failed: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let boltReloadConfig = Notification.Name("boltReloadConfig")
}
