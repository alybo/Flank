import Cocoa

final class EdgeRevealIndicatorController: NSObject {
    private var panel: NSPanel?
    private var monitor: Any?
    private var indicatorFrame: CGRect = .zero
    private var edgeFrame: CGRect = .zero

    var onActivate: (() -> Void)?

    func show(side: DockState.Side, screen: NSScreen, windowFrame: CGRect, edgeWidth: CGFloat, gripWidth: CGFloat) {
        hide()

        let indicatorSize = CGSize(width: 52, height: 92)
        let normalizedFrame = normalizeWindowFrame(windowFrame, in: screen.frame)
        let x = side == .left
            ? screen.frame.minX + gripWidth
            : screen.frame.maxX - gripWidth - indicatorSize.width
        let y = normalizedFrame.midY - indicatorSize.height / 2
        let frame = CGRect(origin: CGPoint(x: x, y: y), size: indicatorSize)

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
        effectView.layer?.cornerRadius = 0
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        effectView.autoresizingMask = [.width, .height]
        applyCornerMask(to: effectView, side: side, radius: 22)

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

    private func normalizeWindowFrame(_ frame: CGRect, in screenFrame: CGRect) -> CGRect {
        let mid = CGPoint(x: frame.midX, y: frame.midY)
        if screenFrame.contains(mid) {
            return frame
        }

        let flippedY = screenFrame.maxY - frame.origin.y - frame.size.height
        let flipped = CGRect(x: frame.origin.x, y: flippedY, width: frame.size.width, height: frame.size.height)
        let flippedMid = CGPoint(x: flipped.midX, y: flipped.midY)
        if screenFrame.contains(flippedMid) {
            return flipped
        }

        return frame
    }

    private func applyCornerMask(to view: NSView, side: DockState.Side, radius: CGFloat) {
        let corners: CornerSet = side == .left ? [.topRight, .bottomRight] : [.topLeft, .bottomLeft]
        let path = roundedCornerPath(in: view.bounds, radius: radius, corners: corners)

        let mask = CAShapeLayer()
        mask.frame = view.bounds
        mask.path = path
        view.layer?.mask = mask
    }

    private struct CornerSet: OptionSet {
        let rawValue: Int
        static let topLeft = CornerSet(rawValue: 1 << 0)
        static let topRight = CornerSet(rawValue: 1 << 1)
        static let bottomRight = CornerSet(rawValue: 1 << 2)
        static let bottomLeft = CornerSet(rawValue: 1 << 3)
    }

    private func roundedCornerPath(in rect: CGRect, radius: CGFloat, corners: CornerSet) -> CGPath {
        let path = CGMutablePath()
        let maxX = rect.maxX
        let minX = rect.minX
        let maxY = rect.maxY
        let minY = rect.minY

        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0

        path.move(to: CGPoint(x: minX + tl, y: maxY))
        path.addLine(to: CGPoint(x: maxX - tr, y: maxY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: maxX - tr, y: maxY - tr), radius: tr, startAngle: .pi / 2, endAngle: 0, clockwise: true)
        }
        path.addLine(to: CGPoint(x: maxX, y: minY + br))
        if br > 0 {
            path.addArc(center: CGPoint(x: maxX - br, y: minY + br), radius: br, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
        }
        path.addLine(to: CGPoint(x: minX + bl, y: minY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: minX + bl, y: minY + bl), radius: bl, startAngle: -.pi / 2, endAngle: .pi, clockwise: true)
        }
        path.addLine(to: CGPoint(x: minX, y: maxY - tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: minX + tl, y: maxY - tl), radius: tl, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
        }
        path.closeSubpath()
        return path
    }
}
