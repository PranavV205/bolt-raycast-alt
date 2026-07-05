import AppKit
import Carbon.HIToolbox

// User-rebindable global hotkeys. Bindings live in ~/.bolt/config.json under
// "hotkeys". Missing keys fall back to the defaults below; "none" disables a
// binding; an invalid combo falls back to the default and shows a toast.
enum HotkeyBindings {

    static let defaults: [String: String] = [
        "toggleLauncher": "option+space",
        "clipboardHistory": "ctrl+option+v",
        "scratchpad": "ctrl+option+s",
        "tileLeft": "ctrl+option+left",
        "tileRight": "ctrl+option+right",
        "tileTop": "ctrl+option+up",
        "tileBottom": "ctrl+option+down",
        "tileTopLeft": "ctrl+option+u",
        "tileTopRight": "ctrl+option+i",
        "tileBottomLeft": "ctrl+option+j",
        "tileBottomRight": "ctrl+option+k",
        "maximize": "ctrl+option+return",
        "center": "ctrl+option+c",
        "nextDisplay": "ctrl+option+n",
    ]

    private static let actions: [String: () -> Void] = [
        "toggleLauncher": { PanelController.shared.toggle() },
        "clipboardHistory": { PanelController.shared.toggle(prefill: "clip ") },
        "scratchpad": { Scratchpad.shared.toggle() },
        "tileLeft": { WindowManager.shared.perform(.leftHalf) },
        "tileRight": { WindowManager.shared.perform(.rightHalf) },
        "tileTop": { WindowManager.shared.perform(.topHalf) },
        "tileBottom": { WindowManager.shared.perform(.bottomHalf) },
        "tileTopLeft": { WindowManager.shared.perform(.topLeftQuarter) },
        "tileTopRight": { WindowManager.shared.perform(.topRightQuarter) },
        "tileBottomLeft": { WindowManager.shared.perform(.bottomLeftQuarter) },
        "tileBottomRight": { WindowManager.shared.perform(.bottomRightQuarter) },
        "maximize": { WindowManager.shared.perform(.maximize) },
        "center": { WindowManager.shared.perform(.center) },
        "nextDisplay": { WindowManager.shared.perform(.nextDisplay) },
    ]

    // Re-reads AppConfig and re-registers every binding. Safe to call again
    // after "Reload Bolt Config".
    static func apply() {
        HotkeyManager.shared.unregisterAll()
        let user = AppConfig.shared.hotkeys
        var problems: [String] = []

        for (name, action) in actions {
            let combo = user[name] ?? defaults[name]!
            if combo.lowercased() == "none" { continue }
            if let parsed = parse(combo) {
                HotkeyManager.shared.register(keyCode: parsed.keyCode, modifiers: parsed.modifiers, handler: action)
            } else {
                problems.append(name)
                if let fallback = parse(defaults[name]!) {
                    HotkeyManager.shared.register(keyCode: fallback.keyCode, modifiers: fallback.modifiers, handler: action)
                }
            }
        }
        for name in user.keys where actions[name] == nil {
            problems.append(name)
        }

        if !problems.isEmpty {
            Toast.show(
                "Invalid hotkey config: \(problems.joined(separator: ", "))",
                symbol: "exclamationmark.triangle.fill",
                duration: 3.5
            )
        }
    }

    // The combo a binding resolves to right now (user value if valid, else
    // default), rendered as glyphs for menus and result hints, e.g. "⌃⌥←".
    static func hint(_ name: String) -> String? {
        guard let def = defaults[name] else { return nil }
        var combo = AppConfig.shared.hotkeys[name] ?? def
        if parse(combo) == nil { combo = def }
        if combo.lowercased() == "none" { return nil }

        var mods = ""
        var key = ""
        for part in combo.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "ctrl", "control": mods += "⌃"
            case "option", "opt", "alt": mods += "⌥"
            case "shift": mods += "⇧"
            case "cmd", "command": mods += "⌘"
            default: key = keyGlyphs[part] ?? part.uppercased()
            }
        }
        return mods + key
    }

    // "ctrl+option+left" -> Carbon key code and modifier mask.
    static func parse(_ combo: String) -> (keyCode: Int, modifiers: Int)? {
        var mods = 0
        var key: Int?
        var isFunctionKey = false

        for part in combo.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command": mods |= cmdKey
            case "ctrl", "control": mods |= controlKey
            case "option", "opt", "alt": mods |= optionKey
            case "shift": mods |= shiftKey
            default:
                guard key == nil, let code = keyCodes[part] else { return nil }
                key = code
                isFunctionKey = part.count > 1 && part.first == "f" && Int(part.dropFirst()) != nil
            }
        }

        guard let keyCode = key else { return nil }
        // A bare key would swallow normal typing; only F-keys may bind alone.
        if mods == 0 && !isFunctionKey { return nil }
        return (keyCode, mods)
    }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return,
        "tab": kVK_Tab, "escape": kVK_Escape, "esc": kVK_Escape,
        "delete": kVK_Delete, "backspace": kVK_Delete,
        "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End,
        "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period,
        "slash": kVK_ANSI_Slash, "semicolon": kVK_ANSI_Semicolon,
        "quote": kVK_ANSI_Quote, "backslash": kVK_ANSI_Backslash,
        "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal,
        "grave": kVK_ANSI_Grave, "backtick": kVK_ANSI_Grave,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
        "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    private static let keyGlyphs: [String: String] = [
        "space": "Space", "return": "⏎", "enter": "⏎", "tab": "⇥",
        "escape": "⎋", "esc": "⎋", "delete": "⌫", "backspace": "⌫",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "comma": ",", "period": ".", "slash": "/", "semicolon": ";",
        "quote": "'", "backslash": "\\", "minus": "-", "equal": "=",
        "grave": "`", "backtick": "`",
    ]
}
