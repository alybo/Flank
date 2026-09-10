import Cocoa

final class EdgeOverlayController: NSObject {
    private var panel: NSPanel?
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var isPointerInside: Bool { panel?.frame.contains(NSEvent.mouseLocation) == true }

    func showOnScreen(side: DockState.Side, screen: NSScreen, width: CGFloat = 6) {
        let frame = screen.frame

        let overlayFrame: CGRect
        switch side {
        case .right:
            overlayFrame = CGRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height)
        case .left:
            overlayFrame = CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height)
        }

        if panel?.frame == overlayFrame { return }
        hide()

        let p = NSPanel(
            contentRect: overlayFrame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = NSColor.clear
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.ignoresMouseEvents = false
        p.hasShadow = false

        let view = TrackingView(frame: overlayFrame)
        view.onMouseEntered = { [weak self] in self?.onEnter?() }
        view.onMouseExited = { [weak self] in self?.onExit?() }
        p.contentView = view

        panel = p
        p.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

final class TrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)

        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
