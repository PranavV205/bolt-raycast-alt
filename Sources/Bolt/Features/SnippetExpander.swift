import AppKit
import Carbon.HIToolbox

// Live text expansion: type ";sig" in any app and it is replaced by the
// snippet content. Implemented as a listen-only CGEvent tap that keeps a
// small rolling buffer of typed characters; on a keyword match it sends
// backspaces to erase the trigger and pastes the expansion.
final class SnippetExpander {
    static let shared = SnippetExpander()

    private var snippets: [Snippet] = []
    private var tap: CFMachPort?
    private var buffer = ""
    private var suppress = false   // true while we inject our own events

    private init() {
        // Reset the buffer when the user switches apps.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.buffer = ""
        }
    }

    func update(snippets: [Snippet]) {
        self.snippets = snippets.filter { $0.keyword.count >= 2 }
    }

    func start(snippets: [Snippet]) {
        update(snippets: snippets)
        guard AppConfig.shared.snippetExpansionEnabled else { return }
        guard AX.trusted else {
            NSLog("Bolt: snippet expansion disabled, Accessibility not granted")
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let expander = Unmanaged<SnippetExpander>.fromOpaque(refcon).takeUnretainedValue()
                expander.handleKeyDown(event: event, type: type)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            NSLog("Bolt: could not create event tap for snippet expansion")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleKeyDown(event: CGEvent, type: CGEventType) {
        // macOS disables taps that stall; re-enable if that happens.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown, !suppress else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Command/control shortcuts are not typing.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            buffer = ""
            return
        }

        if keyCode == 51 { // backspace
            if !buffer.isEmpty { buffer.removeLast() }
            return
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              let chars = nsEvent.characters,
              !chars.isEmpty,
              let scalar = chars.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else {
            // Arrows, escape, function keys: the caret moved, buffer invalid.
            buffer = ""
            return
        }

        buffer += chars
        if buffer.count > 60 {
            buffer = String(buffer.suffix(60))
        }

        if let snippet = snippets.first(where: { buffer.hasSuffix($0.keyword) }) {
            expand(snippet)
        }
    }

    private func expand(_ snippet: Snippet) {
        suppress = true
        buffer = ""
        let keywordLength = snippet.keyword.count
        let content = snippet.expandedContent()

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            suppress = false
            return
        }

        // Erase the typed trigger.
        for _ in 0..<keywordLength {
            let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }

        // Paste the expansion after the backspaces have landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            ClipboardManager.shared.ignoreNextChange = true
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(content, forType: .string)

            let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.suppress = false
            }
        }
    }
}
