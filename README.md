# Clipstack

Clipboard history for macOS, like Win+V. Press **⌘⇧V** to search and paste anything you copied,
including images and files.

Clipstack lives in the menu bar and records everything you copy. Press the shortcut, type to
search, pick an item with the arrow keys or the mouse, and it is pasted straight into the app
you are working in. Built in Swift with AppKit and SwiftUI. No dependencies, no network, no Dock icon.

## Features

- Text (plain and rich), **images**, and files copied in Finder
- Global shortcut **⌘⇧V**, changeable from the menu-bar icon (⌃⌘V, ⌥⌘V, ⌘⇧C)
- Panel opens at the text caret when possible, otherwise at the mouse pointer
- Search as you type, ↩ to paste, ⌘1–⌘9 to paste the nth item
- Pin items so they survive "Clear", ⌘⌫ to delete one
- Image thumbnails with dimensions, source-app icon per item
- Copying the same thing twice moves it to the top instead of duplicating it
- Skips content that password managers mark as concealed
- Persists across restarts, keeps the latest 200 unpinned items
- Launch at login

## Install

Requires macOS 14 or newer and Xcode or the Command Line Tools.

```sh
git clone https://github.com/gormovsisyan/clipstack.git
cd clipstack
./build.sh --install     # builds build/Clipstack.app, copies it to /Applications, launches it
```

`./build.sh --run` builds and launches without installing. You can also open `Package.swift`
in Xcode and run it from there.

## Permissions

1. **Accessibility** (System Settings → Privacy & Security → Accessibility) lets Clipstack
   press ⌘V in the frontmost app. The panel shows an "Enable…" button until it is granted.
   Without it, choosing an item copies it to the clipboard and you press ⌘V yourself.
2. On macOS 26 the system may ask whether Clipstack may **paste from other apps** the first
   time it reads the clipboard. Choose Allow, otherwise nothing can be recorded.

The app is signed ad hoc, and macOS ties the Accessibility grant to that signature, so every
rebuild resets it. To keep the grant across builds, create a self-signed "Code Signing"
certificate in Keychain Access and build with `SIGN_IDENTITY="My Cert Name" ./build.sh`.

## Keyboard

| Key | Action |
| --- | --- |
| ⌘⇧V | Open / close the panel (configurable) |
| ↑ ↓, Page Up/Down, Home/End | Move selection |
| ↩ or click | Paste selected item |
| ⌘1 … ⌘9 | Paste the nth item |
| ⌘C | Copy selected item without pasting |
| ⌘P | Pin / unpin |
| ⌘⌫ | Delete selected item |
| Esc or click outside | Close |
| Right-click an item | Paste, copy, pin, delete |

Left-click the menu-bar icon to open the panel, right-click for options: shortcut, launch at
login, accessibility, clear history, quit.

## Where data lives

`~/Library/Application Support/Clipstack/` holds `history.json` and an `images/` folder with
one PNG per image entry. Delete the folder to reset everything.

## How it works

- `ClipboardMonitor` polls `NSPasteboard.general.changeCount` twice a second and extracts file
  URLs, an image, or text from each change.
- `HistoryStore` de-duplicates by content hash, trims old entries, and saves JSON plus PNG files.
- `HistoryPanel` is a non-activating `NSPanel`, so the app you are using keeps focus.
- `Paster` writes the chosen item back to the pasteboard and synthesizes ⌘V with a `CGEvent`.
- `HotKey` registers the global shortcut with Carbon's `RegisterEventHotKey`, which needs no
  special permission.

See `AGENTS.md` for the file layout and the rules to keep in mind when changing the code.

## Development

```sh
swift build          # compile
./build.sh --run     # release bundle + relaunch
```

Website: [clipstack.landing](https://github.com/gormovsisyan/clipstack.landing).

## License

[MIT](LICENSE)
