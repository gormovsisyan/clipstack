import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Glue between the panel window, the SwiftUI view, keyboard handling and pasting.
final class PanelController {
    let state = PanelState()

    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private var panel: HistoryPanel!
    private var keyMonitor: Any?

    init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor

        let view = HistoryView(
            store: store,
            state: state,
            onPaste: { [weak self] item in self?.paste(item) },
            onCopyOnly: { [weak self] item in self?.copyOnly(item) },
            onEnableAccessibility: { [weak self] in self?.enableAccessibility() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        panel = HistoryPanel(contentView: hosting, size: NSSize(width: HistoryView.width, height: HistoryView.height))
        panel.onHide = { [weak self] in self?.removeKeyMonitor() }

        monitor.onTick = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            let trusted = Paster.isTrusted
            if trusted != self.state.accessibilityTrusted { self.state.accessibilityTrusted = trusted }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(anchor: NSPoint? = nil) {
        if panel.isVisible { hide() } else { show(anchor: anchor) }
    }

    func show(anchor explicitAnchor: NSPoint? = nil) {
        state.searchText = ""
        state.accessibilityTrusted = Paster.isTrusted
        state.selectedID = store.displayItems.first?.id
        state.lastKeyboardNavigation = .distantPast

        let anchor = explicitAnchor ?? Paster.caretAnchor() ?? NSEvent.mouseLocation
        panel.show(topLeftAt: anchor)
        installKeyMonitor()
        state.focusToken += 1
        DispatchQueue.main.async { [weak self] in self?.focusSearchField() }
    }

    func hide() {
        panel.orderOut(nil)
    }

    // MARK: - Actions

    private var currentItems: [ClipItem] { state.filtered(store.displayItems) }

    private var selectedItem: ClipItem? {
        currentItems.first { $0.id == state.selectedID }
    }

    private func paste(_ item: ClipItem) {
        hide()
        guard Paster.write(item, store: store) else { return }
        monitor.skipCurrentChange()
        store.touch(item.id)
        guard Paster.isTrusted else { return }
        // Give the previously focused window a moment to become key again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.sendPasteKeystroke()
        }
    }

    private func copyOnly(_ item: ClipItem) {
        hide()
        guard Paster.write(item, store: store) else { return }
        monitor.skipCurrentChange()
        store.touch(item.id)
    }

    private func enableAccessibility() {
        Paster.requestAccessibility()
    }

    private func removeSelected() {
        let items = currentItems
        guard let index = items.firstIndex(where: { $0.id == state.selectedID }) else { return }
        store.remove(items[index].id)
        let remaining = currentItems
        guard !remaining.isEmpty else { state.selectedID = nil; return }
        state.selectedID = remaining[min(index, remaining.count - 1)].id
        state.lastKeyboardNavigation = Date()
    }

    private func togglePinSelected() {
        guard let item = selectedItem else { return }
        store.togglePin(item.id)
        state.lastKeyboardNavigation = Date()
    }

    private func moveSelection(by delta: Int) {
        let items = currentItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == state.selectedID } ?? -1
        let next = min(max(current + delta, 0), items.count - 1)
        state.selectedID = items[next].id
        state.lastKeyboardNavigation = Date()
    }

    private func selectEdge(first: Bool) {
        let items = currentItems
        state.selectedID = first ? items.first?.id : items.last?.id
        state.lastKeyboardNavigation = Date()
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let characters = event.charactersIgnoringModifiers ?? ""

        if flags == [.command] {
            if event.keyCode == UInt16(kVK_Delete) { removeSelected(); return true }
            switch characters {
            case "p":
                togglePinSelected()
                return true
            case "w":
                hide()
                return true
            case "c":
                if let item = selectedItem { copyOnly(item) }
                return true
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                let index = Int(characters)! - 1
                let items = currentItems
                if index < items.count { paste(items[index]) }
                return true
            default:
                return false
            }
        }

        guard flags.isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_DownArrow: moveSelection(by: 1)
        case kVK_UpArrow: moveSelection(by: -1)
        case kVK_PageDown: moveSelection(by: 6)
        case kVK_PageUp: moveSelection(by: -6)
        case kVK_Home: selectEdge(first: true)
        case kVK_End: selectEdge(first: false)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = selectedItem { paste(item) }
        case kVK_Escape: hide()
        default: return false
        }
        return true
    }

    private func focusSearchField() {
        guard panel.isVisible, let root = panel.contentView,
              let field = Self.findTextField(in: root) else { return }
        panel.makeFirstResponder(field)
    }

    private static func findTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let found = findTextField(in: subview) { return found }
        }
        return nil
    }
}
