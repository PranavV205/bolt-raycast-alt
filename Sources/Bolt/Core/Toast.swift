import AppKit
import SwiftUI

// Small transient HUD used for confirmations ("Copied", "Deployed", errors).
final class Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(
        _ text: String,
        symbol: String = "checkmark.circle.fill",
        duration: TimeInterval = 1.6,
        action: (() -> Void)? = nil
    ) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let view = ToastView(text: text, symbol: symbol, action: action.map { act in
            {
                act()
                panel?.orderOut(nil)
                panel = nil
            }
        })
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = action == nil
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let size = hosting.fittingSize
            let x = vf.midX - size.width / 2
            let y = vf.maxY - size.height - 100
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }
        p.orderFrontRegardless()
        panel = p

        let work = DispatchWorkItem {
            panel?.orderOut(nil)
            panel = nil
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

private struct ToastView: View {
    let text: String
    let symbol: String
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(8)
        .frame(maxWidth: 420)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }
}
