# Clipstack

A native menu-bar clipboard manager that works like the Windows clipboard history (Win+V):
press a shortcut, see everything you copied recently, pick an item, and it is pasted into the
app you are working in.

- Text (plain text plus rich text when available), **images**, and files copied in Finder
- Global shortcut **⌘⇧V** (changeable from the menu-bar icon: ⌃⌘V, ⌥⌘V, ⌘⇧C)
- Popup opens at the text caret when possible, otherwise at the mouse pointer
- Search as you type, arrow keys to move, ↩ to paste, ⌘1–⌘9 to paste the nth item
- Pin items so they survive "Clear", ⌘⌫ to delete one item
- Image thumbnails with dimensions, source-app icon per item
- Persistent across restarts, keeps the latest 200 unpinned items
- Skips passwords from 1Password and other managers that mark clipboard content as concealed
- Menu-bar only, no Dock icon, never steals focus from the app you paste into

## Build and run

Requires Xcode (or the Command Line Tools) on macOS 14 or newer.

```sh
./build.sh --run        # builds build/Clipstack.app and launches it
./build.sh --install    # same, then copies it to /Applications
```

You can also open `Package.swift` in Xcode and run it from there.

## Permissions

1. **Accessibility** (System Settings → Privacy & Security → Accessibility). Needed to send the
   ⌘V keystroke into the frontmost app. The panel shows an "Enable…" button until it is granted.
   Without it, choosing an item copies it to the clipboard and you press ⌘V yourself.
2. On macOS 26 the system may ask whether the app may **paste from other apps** the first time it
   reads the clipboard. Choose Allow, otherwise nothing can be recorded.

The app is signed ad hoc, and macOS ties the Accessibility grant to that signature, so every
rebuild resets it. To keep the grant across builds, create a self-signed "Code Signing"
certificate in Keychain Access and build with `SIGN_IDENTITY="My Cert Name" ./build.sh`.

## Keyboard

| Key | Action |
| --- | --- |
| ⌘⇧V | Open / close the history panel (configurable) |
| ↑ ↓, Page Up/Down, Home/End | Move selection |
| ↩ or click | Paste selected item |
| ⌘1 … ⌘9 | Paste the nth item |
| ⌘C | Copy selected item to the clipboard without pasting |
| ⌘P | Pin / unpin |
| ⌘⌫ | Delete selected item |
| Esc or click outside | Close |
| Right-click an item | Paste, copy, pin, delete |

Left-click the menu-bar icon to open the panel, right-click for options (shortcut, launch at
login, clear history, quit).

## Where data lives

`~/Library/Application Support/Clipstack/` holds `history.json` and an `images/` folder
with one PNG per image entry. Delete the folder to reset everything.

## Layout

```
Sources/Clipstack/
  main.swift            app entry point
  AppDelegate.swift     menu-bar icon, menu, shortcut registration
  ClipboardMonitor.swift  polls NSPasteboard and extracts text / image / file content
  HistoryStore.swift    history list, persistence, thumbnails
  ClipItem.swift        stored entry model
  PanelController.swift shows the panel, keyboard handling, paste flow
  HistoryPanel.swift    non-activating floating NSPanel
  HistoryView.swift     SwiftUI list UI
  Paster.swift          pasteboard writing, ⌘V synthesis, caret lookup
  HotKey.swift          Carbon global hotkey
  Shortcut.swift        shortcut presets
  LaunchAtLogin.swift   SMAppService wrapper
Scripts/make-icon.swift  generates the app icon
build.sh              builds the .app bundle
```
