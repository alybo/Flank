import Cocoa

final class EdgeRevealIndicatorController: NSObject {
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var indicatorFrame: CGRect = .zero
    private var edgeFrame: CGRect = .zero
    private let entrance = PanelEntranceAnimation()

    var onActivate: (() -> Void)?

    func show(side: DockState.Side, screen: NSScreen, edgeWidth: CGFloat) {
        let frame = WindowGeometry.revealIndicatorFrame(in: screen.frame, side: side)
        guard !frame.isEmpty else { hide(); return }
        if panel != nil && indicatorFrame == frame { return }
        hide()
        indicatorFrame = frame
        edgeFrame = CGRect(x: side == .left ? screen.frame.minX : screen.frame.maxX - edgeWidth,
                           y: screen.frame.minY, width: edgeWidth, height: screen.frame.height)

        let panel = NSPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.hasShadow = false

        let view = RevealIndicatorView(frame: CGRect(origin: .zero, size: frame.size), side: side)
        view.autoresizingMask = [.width, .height]
        view.onMouseEntered = { [weak self] in self?.activateIfReady() }
        view.onMouseExited = { [weak self] in self?.hideIfPointerOutside() }
        view.onPress = { [weak self] in self?.activateIfReady() }
        panel.contentView = view
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFront(nil)
        startMonitoringMouse()
        entrance.start(update: { [weak panel] progress in
            panel?.setFrame(PanelEntranceAnimation.frame(at: progress, destination: frame, side: side), display: true)
            panel?.alphaValue = progress
        }, completion: { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel,
                  self.indicatorFrame.contains(NSEvent.mouseLocation) else { return }
            self.activateIfReady()
        })
    }

    func hide() {
        entrance.cancel()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }

    private func activateIfReady() {
        guard panel != nil, !entrance.isRunning else { return }
        onActivate?()
    }

    private func startMonitoringMouse() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            self?.hideIfPointerOutside()
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.hideIfPointerOutside()
            return event
        }) { monitors.append(monitor) }
    }

    private func hideIfPointerOutside() {
        let location = NSEvent.mouseLocation
        if !indicatorFrame.contains(location) && !edgeFrame.contains(location) { hide() }
    }

    deinit { hide() }
}

// The exported Figma asset contains both the body and the white arrow.
final class RevealIndicatorView: NSView {
    private let side: DockState.Side
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onPress: (() -> Void)?

    init(frame: NSRect, side: DockState.Side) {
        self.side = side
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Открыть спрятанное окно")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image = NSImage(named: "FigmaRevealIndicator") else { return }
        NSGraphicsContext.saveGraphicsState()
        if side == .left {
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.width, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.concat()
        }
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
    override func mouseUp(with event: NSEvent) { onPress?() }
    override func accessibilityPerformPress() -> Bool { onPress?(); return onPress != nil }
}
