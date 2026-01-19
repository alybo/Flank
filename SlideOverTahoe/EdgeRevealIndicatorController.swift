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
        private let effectView = NSVisualEffectView()
        private let maskLayer = CAShapeLayer()
        private let highlightMaskLayer = CAShapeLayer()
        private let borderLayer = CAShapeLayer()
        private let innerBorderLayer = CAShapeLayer()
        private let highlightLayer = CAGradientLayer()
        private let chevronLayer = CAShapeLayer()

        init(frame frameRect: NSRect, side: DockState.Side) {
            self.side = side
            super.init(frame: frameRect)
            wantsLayer = true
            effectView.autoresizingMask = [.width, .height]
            addSubview(effectView)
            layer?.addSublayer(borderLayer)
            layer?.addSublayer(innerBorderLayer)
            layer?.addSublayer(highlightLayer)
            layer?.addSublayer(chevronLayer)
            configureLayers()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            effectView.frame = bounds
            updatePaths()
        }

        private func configureLayers() {
            effectView.material = .hudWindow
            effectView.blendingMode = .withinWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.mask = maskLayer
            maskLayer.fillRule = .evenOdd
            maskLayer.fillColor = NSColor.black.cgColor

            borderLayer.fillColor = NSColor.clear.cgColor
            borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.32).cgColor
            borderLayer.lineWidth = 1.2
            borderLayer.fillRule = .evenOdd

            innerBorderLayer.fillColor = NSColor.clear.cgColor
            innerBorderLayer.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
            innerBorderLayer.lineWidth = 0.8
            innerBorderLayer.fillRule = .evenOdd

            highlightLayer.colors = [
                NSColor.white.withAlphaComponent(0.35).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor
            ]
            highlightLayer.startPoint = CGPoint(x: 0.5, y: 1)
            highlightLayer.endPoint = CGPoint(x: 0.5, y: 0)
            highlightLayer.mask = highlightMaskLayer
            highlightMaskLayer.fillRule = .evenOdd
            highlightMaskLayer.fillColor = NSColor.black.cgColor

            chevronLayer.fillColor = NSColor.clear.cgColor
            chevronLayer.strokeColor = NSColor.black.withAlphaComponent(0.82).cgColor
            chevronLayer.lineWidth = 5
            chevronLayer.lineCap = .round
            chevronLayer.lineJoin = .round
        }

        private func updatePaths() {
            let rect = bounds
            let bodyPath = buildPath(width: rect.width, height: rect.height, wMidRatio: 0.56, wMaxRatio: 0.94, yMaxRatio: 0.38)

            maskLayer.frame = rect
            maskLayer.path = bodyPath

            borderLayer.frame = rect
            borderLayer.path = bodyPath

            highlightLayer.frame = rect
            highlightMaskLayer.frame = rect
            highlightMaskLayer.path = bodyPath

            let innerInset: CGFloat = 1.2
            let innerRect = rect.insetBy(dx: innerInset, dy: innerInset)
            let innerPathBase = buildPath(width: innerRect.width, height: innerRect.height, wMidRatio: 0.56, wMaxRatio: 0.94, yMaxRatio: 0.38)
            var translation = CGAffineTransform(translationX: innerRect.minX, y: innerRect.minY)
            let innerPath = innerPathBase.copy(using: &translation) ?? bodyPath
            innerBorderLayer.frame = rect
            innerBorderLayer.path = innerPath

            let chevronPath = CGMutablePath()
            let chevronWidth: CGFloat = 9
            let chevronHeight: CGFloat = 20
            let centerY = rect.midY
            let chevronX = rect.midX
            chevronPath.move(to: CGPoint(x: chevronX + (side == .left ? chevronWidth : -chevronWidth), y: centerY + chevronHeight / 2))
            chevronPath.addLine(to: CGPoint(x: chevronX, y: centerY))
            chevronPath.addLine(to: CGPoint(x: chevronX + (side == .left ? chevronWidth : -chevronWidth), y: centerY - chevronHeight / 2))

            chevronLayer.frame = rect
            chevronLayer.path = chevronPath
        }

        /// buildPath(width:height:wMidRatio:wMaxRatio:yMaxRatio) -> Path
        /// Example: buildPath(width: 40, height: 92, wMidRatio: 0.56, wMaxRatio: 0.94, yMaxRatio: 0.38)
        private func buildPath(width: CGFloat, height: CGFloat, wMidRatio: CGFloat, wMaxRatio: CGFloat, yMaxRatio: CGFloat) -> CGPath {
            let wMax = min(width, width * wMaxRatio)
            let wMid = min(wMax, width * wMidRatio)
            let halfMax = wMax / 2
            let halfMid = wMid / 2
            let centerX = width / 2
            let top = CGPoint(x: centerX, y: 0)
            let bottom = CGPoint(x: centerX, y: height)
            let yMax = height * yMaxRatio
            let rightMax = CGPoint(x: centerX + halfMax, y: yMax)
            let leftMax = CGPoint(x: centerX - halfMax, y: height - yMax)

            let waistY = height / 2
            let waistRight = CGPoint(x: centerX + halfMid, y: waistY)
            let waistLeft = CGPoint(x: centerX - halfMid, y: waistY)

            let controlTop = yMax * 0.45
            let controlBottom = height - (yMax * 0.45)

            let path = CGMutablePath()
            path.move(to: top)
            path.addCurve(to: rightMax,
                          control1: CGPoint(x: centerX, y: controlTop),
                          control2: CGPoint(x: rightMax.x, y: controlTop))
            path.addCurve(to: bottom,
                          control1: CGPoint(x: rightMax.x, y: waistY),
                          control2: CGPoint(x: waistRight.x, y: controlBottom))
            path.addCurve(to: leftMax,
                          control1: CGPoint(x: waistLeft.x, y: controlBottom),
                          control2: CGPoint(x: leftMax.x, y: waistY))
            path.addCurve(to: top,
                          control1: CGPoint(x: leftMax.x, y: controlTop),
                          control2: CGPoint(x: centerX, y: controlTop))
            path.closeSubpath()
            return path
        }
    }
}
