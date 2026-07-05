import AppKit
import Carbon.HIToolbox

// Puts content on the pasteboard and synthesizes Cmd+V into the app the
// user was in. Falls back to plain copy when Accessibility isn't granted.
enum PasteHelper {

    static var canSynthesizePaste: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func paste(text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return synthesizeCmdV()
    }

    @discardableResult
    static func paste(image: NSImage) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        return synthesizeCmdV()
    }

    static func copy(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // Moves the caret left after a synthesized paste has landed, so snippet
    // {cursor} markers work. Delay must exceed the paste's own delay.
    static func moveCaretBack(_ count: Int, after delay: TimeInterval = 0.45) {
        guard count > 0, canSynthesizePaste,
              let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let steps = min(count, 500)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            for _ in 0..<steps {
                let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: false)
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
            }
        }
    }

    private static func synthesizeCmdV() -> Bool {
        guard canSynthesizePaste else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        // Small delay so the launcher panel has fully resigned key and the
        // target app is receiving events again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
        }
        return true
    }
}
