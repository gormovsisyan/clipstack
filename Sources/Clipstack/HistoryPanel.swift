import AppKit

/// Floating, non-activating panel: it can take keyboard focus for search/navigation without
/// activating this app, so the app you were working in stays frontmost and receives the paste.
final class HistoryPanel: NSPanel {
    var onHide: (() -> Void)?
    private var hiding = false

    init(contentView view: NSView, size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        view.frame = effect.bounds
        view.autoresizingMask = [.width, .height]
        effect.addSubview(view)
        contentView = effect
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    override func orderOut(_ sender: Any?) {
        guard !hiding else { return }
        hiding = true
        defer { hiding = false }
        let wasVisible = isVisible
        super.orderOut(sender)
        if wasVisible { onHide?() }
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    /// Shows the panel with its top-left corner at `point`, clamped to the screen under it.
    func show(topLeftAt point: NSPoint) {
        let size = frame.size
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var origin = NSPoint(x: point.x, y: point.y - size.height)
        origin.x = min(origin.x, visible.maxX - size.width)
        origin.x = max(origin.x, visible.minX)
        origin.y = max(origin.y, visible.minY)
        origin.y = min(origin.y, visible.maxY - size.height)
        setFrameOrigin(origin)
        orderFrontRegardless()
        makeKey()
    }
}
