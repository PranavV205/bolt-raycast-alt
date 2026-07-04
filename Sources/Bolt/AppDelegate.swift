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

        // Global hotkeys.
        HotkeyManager.shared.register(keyCode: Keys.space, modifiers: Keys.optionMod) {
            PanelController.shared.toggle()
        }
        HotkeyManager.shared.register(keyCode: Keys.v, modifiers: Keys.controlOptionMod) {
            PanelController.shared.toggle(prefill: "clip ")
        }
        HotkeyManager.shared.register(keyCode: Keys.s, modifiers: Keys.controlOptionMod) {
            Scratchpad.shared.toggle()
        }
        WindowManager.shared.registerHotkeys()

        // Background services.
        ClipboardManager.shared.start()
        SnippetExpander.shared.start(snippets: PanelController.shared.coordinator.snippetsProvider.snippets)
        CurrencyService.shared.refreshIfStale()

        // "Reload Bolt Config" command.
        NotificationCenter.default.addObserver(
            forName: .boltReloadConfig, object: nil, queue: .main
        ) { _ in
            let coordinator = PanelController.shared.coordinator
            coordinator.snippetsProvider.reload()
            coordinator.quicklinksProvider.load()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "bolt.fill",
            accessibilityDescription: "Bolt"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Bolt (Option+Space)", action: #selector(openLauncher), keyEquivalent: "")
        menu.addItem(withTitle: "Clipboard History (Ctrl+Option+V)", action: #selector(openClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "Scratchpad (Ctrl+Option+S)", action: #selector(openScratchpad), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Config Folder", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Bolt", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu

        statusItem = item
    }

    @objc private func openLauncher() { PanelController.shared.show() }
    @objc private func openClipboard() { PanelController.shared.show(prefill: "clip ") }
    @objc private func openScratchpad() { Scratchpad.shared.toggle() }
    @objc private func openConfig() { NSWorkspace.shared.open(AppPaths.configDir) }
    @objc private func quit() { NSApp.terminate(nil) }
}
