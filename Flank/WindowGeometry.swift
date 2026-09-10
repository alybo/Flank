import Cocoa

enum WindowGeometry {
    // AX/CG use top-left coordinates; AppKit uses bottom-left coordinates.
    // The first NSScreen defines the primary coordinate space, unlike NSScreen.main.
    static func appKitFrame(fromAX frame: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
    }

    static func screen(forAX frame: CGRect) -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        let converted = appKitFrame(fromAX: frame, primaryMaxY: primary.frame.maxY)
        return NSScreen.screens.max { lhs, rhs in
            intersectionArea(converted, lhs.frame) < intersectionArea(converted, rhs.frame)
        }
    }

    static func rightEdgeIsExternal(_ screen: CGRect, among screens: [CGRect]) -> Bool {
        edgeIsExternal(screen, side: .right, among: screens)
    }

    static func edgeIsExternal(_ screen: CGRect, side: DockState.Side, among screens: [CGRect]) -> Bool {
        !screen.isEmpty && !screens.contains { other in
            let beyond = side == .right ? other.maxX > screen.maxX + 1 : other.minX < screen.minX - 1
            return beyond && min(other.maxY, screen.maxY) > max(other.minY, screen.minY)
        }
    }

    // Fixed drop region for the entire gesture; independent of the pointer's height.
    static func dropTargetFrame(in screenFrame: CGRect, side: DockState.Side = .right) -> CGRect {
        guard !screenFrame.isEmpty else { return .zero }
        let width = min(252, screenFrame.width)
        return CGRect(x: side == .right ? screenFrame.maxX - width : screenFrame.minX, y: screenFrame.minY,
                      width: width, height: screenFrame.height)
    }

    static func revealIndicatorFrame(in screenFrame: CGRect, side: DockState.Side) -> CGRect {
        guard !screenFrame.isEmpty else { return .zero }
        let size = CGSize(width: min(30, screenFrame.width), height: min(102.5, screenFrame.height))
        return CGRect(x: side == .right ? screenFrame.maxX - size.width : screenFrame.minX,
                      y: screenFrame.midY - size.height / 2, width: size.width, height: size.height)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
