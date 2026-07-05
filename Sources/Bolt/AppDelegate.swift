import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar presence (no Dock icon; activation policy is .accessory).
        setupStatusItem()

        // One-time Accessibility prompt. The hotkey works without it, but
        // window management, menu search, auto-paste and snippet expansion
        // all need it.
        if !AX.trusted {
            AX.promptForTrust()
        }

        // Global hotkeys, user-rebindable via ~/.bolt/config.json.
        HotkeyBindings.apply()

        // Background services.
        ClipboardManager.shared.start()
        SnippetExpander.shared.start(snippets: PanelController.shared.coordinator.snippetsProvider.snippets)
        CurrencyService.shared.refreshIfStale()
        UpdateChecker.shared.checkIfStale()
        _ = AliasStore.shared  // materializes the starter aliases.json

        // "Reload Bolt Config" command.
        NotificationCenter.default.addObserver(
            forName: .boltReloadConfig, object: nil, queue: .main
        ) { [weak self] _ in
            let coordinator = PanelController.shared.coordinator
            coordinator.snippetsProvider.reload()
            coordinator.quicklinksProvider.load()
            AliasStore.shared.load()
            HotkeyBindings.apply()
            self?.rebuildStatusMenu()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "bolt.fill",
            accessibilityDescription: "Bolt"
        )
        statusItem = item
        rebuildStatusMenu()
    }

    // Rebuilt after config reloads so the labels track the user's bindings.
    private func rebuildStatusMenu() {
        func label(_ title: String, _ binding: String) -> String {
            if let hint = HotkeyBindings.hint(binding) { return "\(title) (\(hint))" }
            return title
        }

        let menu = NSMenu()
        menu.addItem(withTitle: label("Open Bolt", "toggleLauncher"), action: #selector(openLauncher), keyEquivalent: "")
        menu.addItem(withTitle: label("Clipboard History", "clipboardHistory"), action: #selector(openClipboard), keyEquivalent: "")
        menu.addItem(withTitle: label("Scratchpad", "scratchpad"), action: #selector(openScratchpad), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Config Folder", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Bolt", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        statusItem?.menu = menu
    }

    @objc private func openLauncher() { PanelController.shared.show() }
    @objc private func openClipboard() { PanelController.shared.show(prefill: "clip ") }
    @objc private func openScratchpad() { Scratchpad.shared.toggle() }
    @objc private func openConfig() { NSWorkspace.shared.open(AppPaths.configDir) }
    @objc private func quit() { NSApp.terminate(nil) }
}
