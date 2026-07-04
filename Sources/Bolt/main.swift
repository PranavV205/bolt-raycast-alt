import AppKit

// Menu-bar agent: no Dock icon, no main window, lives for the hotkey.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
