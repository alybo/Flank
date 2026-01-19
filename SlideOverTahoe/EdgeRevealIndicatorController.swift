import Cocoa

final class EdgeRevealIndicatorController: NSObject {
    private var panel: NSPanel?
    private var monitor: Any?
    private var indicatorFrame: CGRect = .zero
    private var edgeFrame: CGRect = .zero

    var onActivate: (() -> Void)?

    func show(side: DockState.Side, screen: NSScreen, windowFrame: CGRect, edgeWidth: CGFloat, gripWidth: CGFloat) {
        hide()

        let indicatorSize = CGSize(width: 46, height: 92)
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

        let indicatorView = IndicatorView(frame: CGRect(origin: .zero, size: indicatorSize), side: side)
        indicatorView.autoresizingMask = [.width, .height]

        let trackingView = TrackingView(frame: indicatorView.bounds)
        trackingView.onMouseEntered = { [weak self] in
            self?.onActivate?()
        }
        trackingView.onMouseExited = { [weak self] in
            self?.hideIfPointerOutside()
        }
        trackingView.addSubview(indicatorView)
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

    private final class IndicatorView: NSView {
        private let side: DockState.Side
        private let bodyLayer = CAShapeLayer()
        private let borderLayer = CAShapeLayer()
        private let chevronLayer = CAShapeLayer()

        init(frame frameRect: NSRect, side: DockState.Side) {
            self.side = side
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.addSublayer(bodyLayer)
            layer?.addSublayer(borderLayer)
            layer?.addSublayer(chevronLayer)
            configureLayers()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            updatePaths()
        }

        private func configureLayers() {
            bodyLayer.fillColor = NSColor.black.withAlphaComponent(0.65).cgColor
            bodyLayer.shadowColor = NSColor.black.withAlphaComponent(0.45).cgColor
            bodyLayer.shadowOpacity = 1
            bodyLayer.shadowRadius = 10
            bodyLayer.shadowOffset = CGSize(width: 0, height: -1)

            borderLayer.fillColor = NSColor.clear.cgColor
            borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.28).cgColor
            borderLayer.lineWidth = 1

            chevronLayer.fillColor = NSColor.clear.cgColor
            chevronLayer.strokeColor = NSColor.black.withAlphaComponent(0.8).cgColor
            chevronLayer.lineWidth = 6
            chevronLayer.lineCap = .round
            chevronLayer.lineJoin = .round
        }

        private func updatePaths() {
            let rect = bounds
            let radius = rect.width / 2
            let indentation = rect.width * 0.38
            let centerY = rect.midY
            let topY = rect.maxY - 8
            let bottomY = rect.minY + 8
            let outerX = side == .left ? rect.maxX : rect.minX
            let innerX = side == .left ? rect.minX + indentation : rect.maxX - indentation

            let bodyPath = CGMutablePath()
            bodyPath.move(to: CGPoint(x: outerX, y: topY - radius))
            bodyPath.addArc(center: CGPoint(x: outerX, y: topY - radius),
                            radius: radius,
                            startAngle: .pi / 2,
                            endAngle: -.pi / 2,
                            clockwise: true)
            bodyPath.addCurve(to: CGPoint(x: innerX, y: centerY),
                              control1: CGPoint(x: outerX, y: centerY + 22),
                              control2: CGPoint(x: innerX, y: centerY + 16))
            bodyPath.addCurve(to: CGPoint(x: outerX, y: bottomY + radius),
                              control1: CGPoint(x: innerX, y: centerY - 16),
                              control2: CGPoint(x: outerX, y: centerY - 22))
            bodyPath.addArc(center: CGPoint(x: outerX, y: bottomY + radius),
                            radius: radius,
                            startAngle: -.pi / 2,
                            endAngle: .pi / 2,
                            clockwise: true)
            bodyPath.closeSubpath()

            bodyLayer.frame = rect
            bodyLayer.path = bodyPath

            borderLayer.frame = rect
            borderLayer.path = bodyPath

            let chevronPath = CGMutablePath()
            let chevronWidth: CGFloat = 10
            let chevronHeight: CGFloat = 22
            let chevronX = side == .left ? rect.minX + indentation + 6 : rect.maxX - indentation - 6
            chevronPath.move(to: CGPoint(x: chevronX + (side == .left ? chevronWidth : -chevronWidth), y: centerY + chevronHeight / 2))
            chevronPath.addLine(to: CGPoint(x: chevronX, y: centerY))
            chevronPath.addLine(to: CGPoint(x: chevronX + (side == .left ? chevronWidth : -chevronWidth), y: centerY - chevronHeight / 2))

            chevronLayer.frame = rect
            chevronLayer.path = chevronPath
        }
    }
}
