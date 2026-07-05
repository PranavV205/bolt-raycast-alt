import AppKit

// Raycast-style window tiling via the Accessibility API. Acts on the
// focused window of the frontmost app (which stays frontmost because the
// launcher panel is non-activating).
enum WindowAction: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case maximize, almostMaximize, center, nextDisplay

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeftQuarter: return "Top Left Quarter"
        case .topRightQuarter: return "Top Right Quarter"
        case .bottomLeftQuarter: return "Bottom Left Quarter"
        case .bottomRightQuarter: return "Bottom Right Quarter"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .center: return "Center Window"
        case .nextDisplay: return "Move to Next Display"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .topLeftQuarter: return "rectangle.inset.topleft.filled"
        case .topRightQuarter: return "rectangle.inset.topright.filled"
        case .bottomLeftQuarter: return "rectangle.inset.bottomleft.filled"
        case .bottomRightQuarter: return "rectangle.inset.bottomright.filled"
        case .maximize: return "rectangle.fill"
        case .almostMaximize: return "rectangle.center.inset.filled"
        case .center: return "rectangle.inset.filled"
        case .nextDisplay: return "rectangle.on.rectangle"
        }
    }

    // Derived from the live bindings so hints stay honest after rebinding.
    var hotkeyHint: String? {
        guard let name = bindingName else { return nil }
        return HotkeyBindings.hint(name)
    }

    var bindingName: String? {
        switch self {
        case .leftHalf: return "tileLeft"
        case .rightHalf: return "tileRight"
        case .topHalf: return "tileTop"
        case .bottomHalf: return "tileBottom"
        case .topLeftQuarter: return "tileTopLeft"
        case .topRightQuarter: return "tileTopRight"
        case .bottomLeftQuarter: return "tileBottomLeft"
        case .bottomRightQuarter: return "tileBottomRight"
        case .maximize: return "maximize"
        case .center: return "center"
        case .nextDisplay: return "nextDisplay"
        case .almostMaximize: return "almostMaximize"
        }
    }

    var aliases: [String] {
        switch self {
        case .leftHalf: return ["left", "half left"]
        case .rightHalf: return ["right", "half right"]
        case .topHalf: return ["top", "up half"]
        case .bottomHalf: return ["bottom", "down half"]
        case .maximize: return ["fullscreen", "max", "zoom"]
        case .almostMaximize: return ["almost"]
        case .center: return ["centre"]
        case .nextDisplay: return ["move display", "other screen", "next screen"]
        default: return []
        }
    }
}

final class WindowManager {
    static let shared = WindowManager()

    @discardableResult
    func perform(_ action: WindowAction) -> Bool {
        guard AX.trusted else {
            AX.promptForTrust()
            Toast.show("Grant Accessibility access to manage windows", symbol: "exclamationmark.triangle.fill")
            return false
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = AX.focusedWindow(ofPid: app.processIdentifier),
              let position = AX.point(window, kAXPositionAttribute as String),
              let size = AX.size(window, kAXSizeAttribute as String) else {
            return false
        }

        let currentCocoa = AX.cocoaRect(fromAXOrigin: position, size: size)
        let screen = screenContaining(rect: currentCocoa) ?? NSScreen.main
        guard let screen else { return false }
        let vf = screen.visibleFrame

        var target: NSRect
        switch action {
        case .leftHalf:
            target = NSRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .rightHalf:
            target = NSRect(x: vf.midX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .topHalf:
            target = NSRect(x: vf.minX, y: vf.midY, width: vf.width, height: vf.height / 2)
        case .bottomHalf:
            target = NSRect(x: vf.minX, y: vf.minY, width: vf.width, height: vf.height / 2)
        case .topLeftQuarter:
            target = NSRect(x: vf.minX, y: vf.midY, width: vf.width / 2, height: vf.height / 2)
        case .topRightQuarter:
            target = NSRect(x: vf.midX, y: vf.midY, width: vf.width / 2, height: vf.height / 2)
        case .bottomLeftQuarter:
            target = NSRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height / 2)
        case .bottomRightQuarter:
            target = NSRect(x: vf.midX, y: vf.minY, width: vf.width / 2, height: vf.height / 2)
        case .maximize:
            target = vf
        case .almostMaximize:
            target = vf.insetBy(dx: vf.width * 0.05, dy: vf.height * 0.05)
        case .center:
            target = NSRect(
                x: vf.midX - currentCocoa.width / 2,
                y: vf.midY - currentCocoa.height / 2,
                width: currentCocoa.width,
                height: currentCocoa.height
            )
        case .nextDisplay:
            let screens = NSScreen.screens
            guard screens.count > 1, let idx = screens.firstIndex(of: screen) else {
                Toast.show("Only one display connected", symbol: "display")
                return false
            }
            let next = screens[(idx + 1) % screens.count].visibleFrame
            let width = min(currentCocoa.width, next.width)
            let height = min(currentCocoa.height, next.height)
            target = NSRect(
                x: next.midX - width / 2,
                y: next.midY - height / 2,
                width: width,
                height: height
            )
        }

        apply(target: target, to: window)
        return true
    }

    private func apply(target: NSRect, to window: AXUIElement) {
        let origin = AX.axOrigin(fromCocoaRect: target)
        // Position, size, position again: some apps clamp the first move
        // until the window shrinks onto the destination screen.
        AX.setPoint(window, kAXPositionAttribute as String, origin)
        AX.setSize(window, kAXSizeAttribute as String, target.size)
        AX.setPoint(window, kAXPositionAttribute as String, origin)
    }

    private func screenContaining(rect: NSRect) -> NSScreen? {
        let mid = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(mid) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
    }

}

// Exposes the tiling actions as launcher results ("left half", "maximize").
final class WindowCommandProvider: SearchProvider {
    let name = "Window"

    func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty, query.trimmed.count >= 2 else { return [] }
        var items: [ResultItem] = []
        for action in WindowAction.allCases {
            let fields = [action.title] + action.aliases + ["window " + action.title.lowercased()]
            guard let score = FuzzyMatcher.score(query: query.lowercased, fields: fields) else { continue }
            items.append(ResultItem(
                id: "window:\(action.rawValue)",
                title: action.title,
                subtitle: "Window management",
                icon: .symbol(action.symbol),
                kind: .command,
                score: score * 0.85,
                accessory: action.hotkeyHint,
                action: { _ in
                    WindowManager.shared.perform(action)
                    return .dismiss
                }
            ))
        }
        return items
    }
}
