import AppKit
import Carbon.HIToolbox

// Global hotkeys via Carbon RegisterEventHotKey. Unlike NSEvent global
// monitors this needs no Accessibility permission and cannot observe
// keystrokes, it only fires for the registered combos.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var nextId: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        if eventHandlerRef == nil { installDispatcher() }
        let id = nextId
        nextId += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x424F_4C54), id: id) // "BOLT"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr {
            handlers[id] = handler
            hotKeyRefs.append(ref)
        } else {
            NSLog("Bolt: failed to register hotkey keyCode=\(keyCode) mods=\(modifiers) status=\(status)")
        }
    }

    private func installDispatcher() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                DispatchQueue.main.async { manager.handlers[hkID.id]?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
}

// Carbon key codes and modifier masks used across the app.
enum Keys {
    static let space = kVK_Space
    static let returnKey = kVK_Return
    static let escape = kVK_Escape
    static let leftArrow = kVK_LeftArrow
    static let rightArrow = kVK_RightArrow
    static let downArrow = kVK_DownArrow
    static let upArrow = kVK_UpArrow
    static let c = kVK_ANSI_C
    static let n = kVK_ANSI_N
    static let s = kVK_ANSI_S
    static let v = kVK_ANSI_V
    static let u = kVK_ANSI_U
    static let i = kVK_ANSI_I
    static let j = kVK_ANSI_J
    static let k = kVK_ANSI_K

    static let optionMod = optionKey
    static let controlOptionMod = controlKey | optionKey
}
