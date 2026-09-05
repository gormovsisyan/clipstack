import AppKit
import Carbon.HIToolbox

/// A preset global shortcut. Stored by index in UserDefaults.
struct Shortcut {
    let name: String
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyEquivalent: String
    let modifierMask: NSEvent.ModifierFlags

    static let presets: [Shortcut] = [
        Shortcut(name: "⌘⇧V", keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | shiftKey),
                 keyEquivalent: "v", modifierMask: [.command, .shift]),
        Shortcut(name: "⌃⌘V", keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | controlKey),
                 keyEquivalent: "v", modifierMask: [.command, .control]),
        Shortcut(name: "⌥⌘V", keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | optionKey),
                 keyEquivalent: "v", modifierMask: [.command, .option]),
        Shortcut(name: "⌘⇧C", keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(cmdKey | shiftKey),
                 keyEquivalent: "c", modifierMask: [.command, .shift]),
    ]

    private static let defaultsKey = "shortcutIndex"

    static var currentIndex: Int {
        get {
            let index = UserDefaults.standard.integer(forKey: defaultsKey)
            return presets.indices.contains(index) ? index : 0
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static var current: Shortcut { presets[currentIndex] }
}
