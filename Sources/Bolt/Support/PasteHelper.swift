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
