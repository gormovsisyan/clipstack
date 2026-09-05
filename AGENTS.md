# Clipstack: guide for coding agents

Clipstack is a menu-bar clipboard history app for macOS, like Win+V on Windows. It records
text, images, and files from the pasteboard and pastes them back into the frontmost app from a
floating panel opened with a global shortcut (default ⌘⇧V).

Stack: Swift 5 language mode, Swift Package Manager, AppKit + SwiftUI, Carbon for the hotkey.
Deployment target macOS 14. No third-party dependencies, no network access, no analytics.

## Build, run, verify

| Command | What it does |
| --- | --- |
| `swift build` | Debug compile. Must finish with zero errors and zero warnings. |
| `./build.sh` | Release build, assembles `build/Clipstack.app`, generates the icon, ad-hoc signs. |
| `./build.sh --run` | Same, then quits any running copy and launches the new one. |
| `./build.sh --install` | Same, then copies to `/Applications` and launches. |
| `./build.sh --package` | Same, then zips the bundle to `build/Clipstack.zip` (what the release workflow ships). |
| `swift run` | Quick launch without a bundle. Launch-at-login and the Dock-less policy need the bundle. |

There is no test target yet. Verify behaviour end to end:

```sh
./build.sh --run
printf 'hello' | pbcopy; sleep 1.5
cat ~/Library/Application\ Support/Clipstack/history.json | python3 -m json.tool | head
log show --predicate 'process == "Clipstack"' --last 5m --style compact
```

Screenshots of the panel cannot be taken from a terminal without Screen Recording permission.
If you need to see the UI, temporarily render the panel's content view with
`NSView.cacheDisplay(in:to:)` to a PNG, then remove the hook before committing.

Releases: push a tag `vX.Y.Z` and `.github/workflows/release.yml` builds, stamps the version
from the tag, attaches `Clipstack.zip` to a GitHub release, and bumps `version`/`sha256` in
`gormovsisyan/homebrew-tap` (needs the `TAP_TOKEN` secret). `ci.yml` compiles on every push.
The cask lives in the tap repo, not here.

## Layout

```
Package.swift             SwiftPM manifest (tools 5.9, links Carbon and ServiceManagement)
Info.plist                bundle metadata, LSUIElement = true
build.sh                  builds the .app bundle
Scripts/make-icon.swift   draws AppIcon.icns with AppKit + iconutil
Sources/Clipstack/
  main.swift              NSApplication bootstrap, accessory activation policy
  AppDelegate.swift       status item, menu, shortcut registration
  ClipboardMonitor.swift  polls NSPasteboard, decides what a change contains
  Captured.swift          raw pasteboard content + content hash
  ClipItem.swift          stored entry model (Codable)
  HistoryStore.swift      list, dedupe, trimming, JSON + PNG persistence, thumbnails
  PanelController.swift   shows the panel, keyboard handling, paste flow
  HistoryPanel.swift      non-activating floating NSPanel
  HistoryView.swift       SwiftUI panel UI + PanelState
  Paster.swift            pasteboard writing, ⌘V synthesis, caret lookup via AX
  HotKey.swift            Carbon RegisterEventHotKey wrapper
  Shortcut.swift          shortcut presets stored in UserDefaults
  LaunchAtLogin.swift     SMAppService wrapper
```

## Architecture rules

1. **The app never activates.** The panel is a `.nonactivatingPanel` so the app the user is
   working in keeps focus and receives the synthesized ⌘V. Never call `NSApp.activate`, never
   switch the activation policy to `.regular`, never present regular windows.
2. **The pasteboard is polled.** macOS has no change notification. `ClipboardMonitor` checks
   `changeCount` every 0.5 s. After Clipstack itself writes to the pasteboard, call
   `monitor.skipCurrentChange()` so the write is not re-captured.
3. **Content precedence** in `ClipboardMonitor.read()`: file URLs, then image, then text. The
   one exception: when both a string and RTF are present alongside an image (Office apps do
   this), prefer the text. Keep the concealed/transient pasteboard type skip list intact.
4. **Persistence format is a compatibility surface.** `history.json` holds `[ClipItem]` with
   ISO 8601 dates; images live in `images/<uuid>.png`. New `ClipItem` fields must be optional
   with defaults so old files still decode.
5. **Keyboard handling** lives in `PanelController.handleKey` via a local `NSEvent` monitor,
   not in SwiftUI `onKeyPress`. Typing that is not a handled shortcut falls through to the
   search field.
6. **Pasting needs Accessibility.** Check `Paster.isTrusted`; without it, fall back to
   copying only and show the banner. Never block the UI on the permission prompt.
7. **Main thread only.** Classes are not `@MainActor`-annotated (Timer and event-monitor
   closures are nonisolated), so keep all state mutation on the main thread by construction.
8. **Privacy.** Never log clipboard contents. Never send anything over the network.

## Temporary: panel theme toggle

`UITheme` switches the panel between `classic` (default) and the experimental `cards` look
(`CardsHistoryView.swift`). It is exposed as the "New UI (test)" menu item and ⌘T in the
panel, persisted in UserDefaults under `uiTheme`. This exists for evaluation only; once a
direction is chosen, keep one theme and delete the toggle.

## Conventions

- 4-space indentation, `// MARK: -` sections, comments explain why, not what.
- User-facing strings use sentence case and the product name "Clipstack".
- `HistoryView.width` / `.height` define the panel size; the panel reads them, so change the
  constants rather than hardcoding sizes elsewhere.
- Keep `README.md` in sync when shortcuts, permissions, or the data location change.

## Gotchas

- Ad-hoc signing produces a new signature every build, which resets the Accessibility grant.
  `SIGN_IDENTITY="<self-signed cert>" ./build.sh` keeps it stable.
- A titled window with `fullSizeContentView` gives SwiftUI a top safe-area inset. The root view
  uses `.ignoresSafeArea()` and the hosting view sets `safeAreaRegions = []`. Removing either
  clips the footer.
- macOS 26 shows a "paste from other apps" consent prompt the first time the app reads the
  pasteboard. `changeCount` and `types` do not trigger it; reading data does.
- In zsh, unquoted `$VAR` does not word-split. Quote or loop over file lists in scripts.
- The hotkey default ⌘⇧V collides with "Paste and Match Style" in many apps; that is why the
  menu offers alternative presets.
