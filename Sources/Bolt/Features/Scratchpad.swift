import AppKit

// Floating quick-note window (Ctrl+Option+S or "note" in the launcher).
// Content autosaves to Application Support and survives restarts.
final class Scratchpad: NSObject, NSWindowDelegate, NSTextViewDelegate {
    static let shared = Scratchpad()

    private var panel: NSPanel?
    private var textView: NSTextView?
    private var saveWork: DispatchWorkItem?

    func toggle() {
        if let panel, panel.isVisible {
            save()
            panel.orderOut(nil)
            return
        }
        showWindow()
    }

    private func showWindow() {
        if panel == nil { buildWindow() }
        guard let panel, let textView else { return }

        textView.string = (try? String(contentsOf: AppPaths.scratchpadFile, encoding: .utf8)) ?? ""
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    private func buildWindow() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Scratchpad"
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.center()

        let scroll = NSScrollView(frame: p.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let tv = NSTextView(frame: scroll.bounds)
        tv.autoresizingMask = [.width]
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.delegate = self

        scroll.documentView = tv
        p.contentView?.addSubview(scroll)

        panel = p
        textView = tv
    }

    func textDidChange(_ notification: Notification) {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func windowWillClose(_ notification: Notification) {
        save()
    }

    private func save() {
        guard let text = textView?.string else { return }
        try? text.write(to: AppPaths.scratchpadFile, atomically: true, encoding: .utf8)
    }
}
