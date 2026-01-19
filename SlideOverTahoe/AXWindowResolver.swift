import Foundation
import ApplicationServices
import CoreGraphics

final class AXWindowResolver {
    static func resolveAXWindow(pid: pid_t, cgBounds: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)

        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let windows = value as? [AXUIElement] else { return nil }

        func axFrame(_ w: AXUIElement) -> CGRect? {
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success,
                AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef) == .success,
                let posVal = posRef, let sizeVal = sizeRef
            else { return nil }

            var p = CGPoint.zero
            var s = CGSize.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &p)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &s)
            return CGRect(origin: p, size: s)
        }

        // Выберем окно с минимальной разницей по центру
        let targetCenter = CGPoint(x: cgBounds.midX, y: cgBounds.midY)

        var best: (AXUIElement, CGFloat)?
        for w in windows {
            guard let f = axFrame(w) else { continue }
            let c = CGPoint(x: f.midX, y: f.midY)
            let dx = c.x - targetCenter.x
            let dy = c.y - targetCenter.y
            let dist = sqrt(dx*dx + dy*dy)

            if best == nil || dist < best!.1 {
                best = (w, dist)
            }
        }
        return best?.0
    }

    static func resolveFocusedOrFirstWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)

        // 1) Focused window (best match)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
           let w = focused {
            return (w as! AXUIElement)
        }

        // 2) Fallback to first window
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement],
           let first = windows.first {
            return first
        }

        return nil
    }
}
