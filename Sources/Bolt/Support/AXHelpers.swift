import AppKit
import ApplicationServices

// Thin wrappers over the Accessibility C API.
enum AX {

    static var trusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return ref
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        attribute(element, name) as? Bool
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let ref = attribute(element, kAXChildrenAttribute as String),
              let array = ref as? [AnyObject] else { return [] }
        return array.map { $0 as! AXUIElement } // CFArray of AXUIElement
    }

    static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let ref = attribute(element, name) else { return nil }
        var value = CGPoint.zero
        guard AXValueGetValue(ref as! AXValue, .cgPoint, &value) else { return nil }
        return value
    }

    static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let ref = attribute(element, name) else { return nil }
        var value = CGSize.zero
        guard AXValueGetValue(ref as! AXValue, .cgSize, &value) else { return nil }
        return value
    }

    @discardableResult
    static func setPoint(_ element: AXUIElement, _ name: String, _ point: CGPoint) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, _ name: String, _ size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func focusedWindow(ofPid pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let ref = attribute(app, kAXFocusedWindowAttribute as String) else { return nil }
        return (ref as! AXUIElement)
    }

    // AX coordinates use a top-left origin on the primary screen,
    // Cocoa uses bottom-left. These convert between the two.
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func cocoaRect(fromAXOrigin origin: CGPoint, size: CGSize) -> NSRect {
        NSRect(x: origin.x, y: primaryScreenHeight - origin.y - size.height,
               width: size.width, height: size.height)
    }

    static func axOrigin(fromCocoaRect rect: NSRect) -> CGPoint {
        CGPoint(x: rect.minX, y: primaryScreenHeight - rect.maxY)
    }
}
