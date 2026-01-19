import Cocoa

final class EdgeRevealIndicatorController: NSObject {
    private var panel: NSPanel?
    private var monitor: Any?
    private var indicatorFrame: CGRect = .zero
    private var edgeFrame: CGRect = .zero

    var onActivate: (() -> Void)?

    func show(side: DockState.Side, screen: NSScreen, windowFrame: CGRect, edgeWidth: CGFloat) {
        hide()

        let indicatorSize = CGSize(width: 52, height: 92)
        let x = side == .left ? screen.frame.minX : screen.frame.maxX - indicatorSize.width
        let y = windowFrame.midY - indicatorSize.height / 2
        let clampedY = min(max(y, screen.frame.minY + 10), screen.frame.maxY - indicatorSize.height - 10)
        let frame = CGRect(origin: CGPoint(x: x, y: clampedY), size: indicatorSize)

        indicatorFrame = frame
        edgeFrame = CGRect(
            x: side == .left ? screen.frame.minX : screen.frame.maxX - edgeWidth,
            y: screen.frame.minY,
            width: edgeWidth,
            height: screen.frame.height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.hasShadow = true

        let effectView = NSVisualEffectView(frame: CGRect(origin: .zero, size: indicatorSize))
        effectView.material = .fullScreenUI
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 22
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        effectView.autoresizingMask = [.width, .height]

        let symbolName = side == .left ? "chevron.right" : "chevron.left"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.contentTintColor = NSColor.white.withAlphaComponent(0.95)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.symbolConfiguration = .init(pointSize: 26, weight: .semibold)
        effectView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: effectView.centerYAnchor)
        ])

        let trackingView = TrackingView(frame: effectView.bounds)
        trackingView.onMouseEntered = { [weak self] in
            self?.onActivate?()
        }
        trackingView.onMouseExited = { [weak self] in
            self?.hideIfPointerOutside()
        }
        trackingView.addSubview(effectView)
        trackingView.autoresizingMask = [.width, .height]

        panel.contentView = trackingView
        self.panel = panel
        panel.orderFront(nil)

        startMonitoringMouse()
    }

    func hide() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func startMonitoringMouse() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.hideIfPointerOutside()
        }
    }

    private func hideIfPointerOutside() {
        let location = NSEvent.mouseLocation
        if !indicatorFrame.contains(location) && !edgeFrame.contains(location) {
            hide()
        }
    }
}
