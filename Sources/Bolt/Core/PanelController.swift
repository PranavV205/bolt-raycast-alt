import AppKit
import Combine
import SwiftUI

// Borderless panel that can still take keyboard input.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// Owns the floating search window: summon, dismiss, keyboard routing, sizing.
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    let coordinator = SearchCoordinator()
    private var panel: LauncherPanel!
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private(set) var targetApp: NSRunningApplication?

    private let panelWidth: CGFloat = 660
    private let fieldHeight: CGFloat = 58
    private let rowHeight: CGFloat = 46
    private let footerHeight: CGFloat = 28
    private let maxVisibleRows = 9

    private override init() {
        super.init()
        buildPanel()

        coordinator.onOutcome = { [weak self] outcome in
            self?.handle(outcome)
        }
        coordinator.$results
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in self?.layout(rowCount: items.count) }
            .store(in: &cancellables)
    }

    private func buildPanel() {
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: fieldHeight + footerHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: SearchView(coordinator: coordinator))
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(prefill: String = "") {
        if panel.isVisible {
            hide()
        } else {
            show(prefill: prefill)
        }
    }

    func show(prefill: String = "") {
        // Remember which app the user was in; window management, menu search
        // and paste all target it. Our panel never activates, so it stays
        // frontmost from the system's point of view.
        targetApp = NSWorkspace.shared.frontmostApplication

        coordinator.prepareForOpen(targetApp: targetApp)
        layout(rowCount: coordinator.results.count)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()

        DispatchQueue.main.async { [weak self] in
            self?.focusField()
            if !prefill.isEmpty {
                self?.coordinator.setQuery(prefill)
            }
        }
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func focusField() {
        guard let tf = coordinator.textField else { return }
        panel.makeFirstResponder(tf)
        if let editor = tf.currentEditor() {
            editor.selectedRange = NSRange(location: tf.stringValue.count, length: 0)
        }
    }

    private func layout(rowCount: Int) {
        let visible = min(rowCount, maxVisibleRows)
        let listHeight = visible > 0 ? CGFloat(visible) * rowHeight + 9 : 0
        let height = fieldHeight + listHeight + footerHeight

        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.midX - panelWidth / 2
        let topY = vf.minY + vf.height * 0.78
        let frame = NSRect(x: x, y: topY - height, width: panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    private func handle(_ outcome: ActionOutcome) {
        switch outcome {
        case .dismiss:
            hide()
        case .toast(let message):
            hide()
            Toast.show(message)
        case .stay:
            break
        case .replaceQuery(let text):
            coordinator.setQuery(text)
        }
    }

    // MARK: keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags

        switch Int(event.keyCode) {
        case Keys.escape:
            hide()
            return true
        case Keys.downArrow:
            coordinator.moveSelection(1)
            return true
        case Keys.upArrow:
            coordinator.moveSelection(-1)
            return true
        case Keys.returnKey, 76: // 76 = keypad enter
            coordinator.executeSelected(modifiers: flags)
            return true
        default:
            break
        }

        // Emacs-style list navigation.
        if flags.contains(.control) {
            if Int(event.keyCode) == Keys.n {
                coordinator.moveSelection(1)
                return true
            }
            if Int(event.keyCode) == 35 { // p
                coordinator.moveSelection(-1)
                return true
            }
        }

        // Cmd+1...9 run the nth result directly.
        if flags.contains(.command), let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), digit >= 1, digit <= 9 {
            coordinator.execute(at: digit - 1, modifiers: flags.subtracting(.command))
            return true
        }

        return false
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // FR-2: losing focus dismisses the launcher.
        hide()
    }
}
