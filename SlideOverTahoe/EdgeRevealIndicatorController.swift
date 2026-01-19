import Cocoa

final class EdgeRevealIndicatorController: NSObject {
    private var panel: NSPanel?
    private var monitor: Any?
    private var indicatorFrame: CGRect = .zero
    private var edgeFrame: CGRect = .zero

    var onActivate: (() -> Void)?

    func show(side: DockState.Side, screen: NSScreen, windowFrame: CGRect, edgeWidth: CGFloat, gripWidth: CGFloat) {
        hide()

        let indicatorSize = CGSize(width: 40, height: 92)
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
        private let gradientLayer = CAGradientLayer()
        private let maskLayer = CAShapeLayer()
        private let borderLayer = CAShapeLayer()
        private let chevronLayer = CAShapeLayer()

        init(frame frameRect: NSRect, side: DockState.Side) {
            self.side = side
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.addSublayer(gradientLayer)
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
            gradientLayer.colors = [
                NSColor(white: 0.28, alpha: 0.96).cgColor,
                NSColor(white: 0.20, alpha: 0.96).cgColor
            ]
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.mask = maskLayer
            maskLayer.fillRule = .evenOdd
            maskLayer.fillColor = NSColor.black.cgColor

            borderLayer.fillColor = NSColor.clear.cgColor
            borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.3).cgColor
            borderLayer.lineWidth = 1
            borderLayer.fillRule = .evenOdd

            chevronLayer.fillColor = NSColor.clear.cgColor
            chevronLayer.strokeColor = NSColor.black.withAlphaComponent(0.85).cgColor
            chevronLayer.lineWidth = 5
            chevronLayer.lineCap = .round
            chevronLayer.lineJoin = .round
        }

        private func updatePaths() {
            let rect = bounds
            let radius = rect.width / 2
            let outerRect = rect.insetBy(dx: 0, dy: 8)
            let bodyPath = CGMutablePath()
            bodyPath.addRoundedRect(in: outerRect, cornerWidth: radius, cornerHeight: radius)

            let notchRadius = rect.height * 0.22
            let notchCenterX = rect.midX
            let notchCenter = CGPoint(x: notchCenterX, y: rect.midY)
            bodyPath.addEllipse(in: CGRect(x: notchCenter.x - notchRadius,
                                           y: notchCenter.y - notchRadius,
                                           width: notchRadius * 2,
                                           height: notchRadius * 2))

            gradientLayer.frame = rect
            maskLayer.frame = rect
            maskLayer.path = bodyPath

            borderLayer.frame = rect
            borderLayer.path = bodyPath

            let chevronPath = CGMutablePath()
            let chevronWidth: CGFloat = 9
            let chevronHeight: CGFloat = 20
            let chevronX = notchCenter.x
            let centerY = rect.midY
            chevronPath.move(to: CGPoint(x: chevronX + (side == .left ? chevronWidth : -chevronWidth), y: centerY + chevronHeight / 2))
            chevronPath.addLine(to: CGPoint(x: chevronX, y: centerY))
            chevronPath.addLine(to: CGPoint(x: chevronX + (side == .left ? chevronWidth : -chevronWidth), y: centerY - chevronHeight / 2))

            chevronLayer.frame = rect
            chevronLayer.path = chevronPath
        }
    }
}
