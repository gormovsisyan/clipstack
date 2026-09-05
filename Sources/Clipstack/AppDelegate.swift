import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var panelController: PanelController!
    private var hotKey: HotKey?
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = HistoryStore()
        monitor = ClipboardMonitor()
        panelController = PanelController(store: store, monitor: monitor)

        monitor.onCapture = { [weak self] captured, source in
            self?.store.ingest(captured, source: source)
        }
        monitor.start()

        setupStatusItem()
        registerHotKey(Shortcut.current)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipstack")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.autoenablesItems = false
        rebuildMenu()
        updateToolTip()
    }

    private func updateToolTip() {
        statusItem.button?.toolTip = "Clipstack — \(Shortcut.current.name) to open, right-click for options"
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let show = NSMenuItem(title: "Show Clipstack", action: #selector(showPanel), keyEquivalent: Shortcut.current.keyEquivalent)
        show.keyEquivalentModifierMask = Shortcut.current.modifierMask
        show.target = self
        menu.addItem(show)

        let shortcutMenu = NSMenu()
        for (index, preset) in Shortcut.presets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(selectShortcut(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = index == Shortcut.currentIndex ? .on : .off
            shortcutMenu.addItem(item)
        }
        let shortcutItem = NSMenuItem(title: "Keyboard Shortcut", action: nil, keyEquivalent: "")
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)

        let newUI = NSMenuItem(title: "New UI (test)", action: #selector(toggleTheme), keyEquivalent: "")
        newUI.target = self
        newUI.state = panelController.theme == .cards ? .on : .off
        newUI.toolTip = "Temporary: switch between the current panel style and the Cards redesign (⌘T in the panel)"
        menu.addItem(newUI)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.isEnabled = LaunchAtLogin.isAvailable
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        if !LaunchAtLogin.isAvailable { login.toolTip = "Available when running from the .app bundle" }
        menu.addItem(login)

        let accessibility = NSMenuItem(title: "Accessibility Access…", action: #selector(openAccessibility), keyEquivalent: "")
        accessibility.target = self
        accessibility.state = Paster.isTrusted ? .on : .off
        menu.addItem(accessibility)

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.toolTip = "Removes everything except pinned items"
        menu.addItem(clear)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Clipstack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            rebuildMenu()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            let anchor: NSPoint? = statusItem.button?.window.map { window in
                NSPoint(x: window.frame.minX, y: window.frame.minY - 4)
            }
            panelController.toggle(anchor: anchor)
        }
    }

    // MARK: - Menu actions

    @objc private func showPanel() {
        panelController.show()
    }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        Shortcut.currentIndex = sender.tag
        registerHotKey(Shortcut.current)
        rebuildMenu()
        updateToolTip()
    }

    @objc private func toggleTheme() {
        panelController.toggleTheme()
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func openAccessibility() {
        Paster.requestAccessibility()
    }

    @objc private func clearHistory() {
        store.clear(keepPinned: true)
    }

    // MARK: - Hotkey

    private func registerHotKey(_ shortcut: Shortcut) {
        hotKey = nil
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
            self?.panelController.toggle()
        }
        if hotKey == nil {
            NSLog("Clipstack: could not register global shortcut \(shortcut.name)")
        }
    }
}
