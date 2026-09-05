import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Writes a history entry back to the pasteboard and (with Accessibility access) sends ⌘V
/// to the app that had focus before the panel opened.
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    static func write(_ item: ClipItem, store: HistoryStore) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            let pbItem = NSPasteboardItem()
            pbItem.setString(text, forType: .string)
            if let rtf = item.rtf { pbItem.setData(rtf, forType: .rtf) }
            return pasteboard.writeObjects([pbItem])
        case .image:
            guard let png = store.imageData(for: item) else { return false }
            let pbItem = NSPasteboardItem()
            pbItem.setData(png, forType: .png)
            if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                pbItem.setData(tiff, forType: .tiff)
            }
            return pasteboard.writeObjects([pbItem])
        case .files:
            let urls = (item.files ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return false }
            return pasteboard.writeObjects(urls)
        }
    }

    static func sendPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Bottom-left corner of the text caret in the focused app (AppKit screen coordinates),
    /// so the panel can open right where the user is typing, like Win+V does.
    static func caretAnchor() -> NSPoint? {
        guard isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         rangeRef, &boundsRef) == .success,
              let boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.height > 0, rect.origin != .zero, rect.width < 2000, rect.height < 500 else { return nil }

        // Accessibility uses a top-left origin on the primary display; AppKit uses bottom-left.
        guard let primary = NSScreen.screens.first else { return nil }
        let point = NSPoint(x: rect.minX, y: primary.frame.maxY - rect.maxY)
        guard NSScreen.screens.contains(where: { NSMouseInRect(point, $0.frame, false) }) else { return nil }
        return NSPoint(x: point.x, y: point.y - 6)
    }
}
