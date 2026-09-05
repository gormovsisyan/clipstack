import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon, never steals focus from the app you are pasting into.
app.setActivationPolicy(.accessory)
app.run()
