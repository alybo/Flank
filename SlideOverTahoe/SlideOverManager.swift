import Foundation
import ApplicationServices
import CoreGraphics
import Cocoa
import Combine

struct DockState {
    let axWindow: AXUIElement
    let ownerPID: pid_t
    let originalFrame: CGRect

    // Last known on-screen frame while visible (kept in sync to handle manual move/resize)
    var lastVisibleFrame: CGRect

    // Screen frame where the window lives (mutable so we can update when it moves screens)
    var screenFrame: CGRect

    let side: Side
    let grip: CGFloat
    var isHidden: Bool
    var settings: EdgeSettings

    enum Side { case left, right }
}

final class SlideOverManager: ObservableObject {
    @Published var state: DockState?

    init() {
        SlideOverManagerRegistry.shared.register(self)
    }

    // Cursor-leave hide
    private var cursorLeaveTimer: Timer?
    private var globalMonitors: [Any] = []
    private var lastMouseInside: Bool = false
    private var hasEnteredTargetSinceShow: Bool = false

    // Inactivity hide (when user switches to another app)
    private var inactiveHideTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastActivatedPID: pid_t?
    private var lastTerminationPID: pid_t?
    private var lastTerminationAt: Date?

    // Sync the target window frame while visible (handles manual move/resize)
    private var frameSyncTimer: Timer?
    private var isAnimatingMove: Bool = false

    func dock(axWindow: AXUIElement, ownerPID: pid_t, side: DockState.Side, grip: CGFloat = 4, settings: EdgeSettings) {
        guard let frame = getFrame(axWindow) else { return }

        // Экран, на котором окно (по центру)
        let screen = screenForPoint(CGPoint(x: frame.midX, y: frame.midY)) ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? .zero

        let s = DockState(
            axWindow: axWindow,
            ownerPID: ownerPID,
            originalFrame: frame,
            lastVisibleFrame: frame,
            screenFrame: screenFrame,
            side: side,
            grip: grip,
            isHidden: false,
            settings: settings
        )
        state = s
        hide(animated: false)

        // Ensure app activation monitoring is active even before first reveal.
        startInactivityMonitoring()
    }

    func updateSettings(_ settings: EdgeSettings) {
        guard var s = state else { return }
        s.settings = settings
        state = s

        // Always monitor app activation while docked (needed to reveal on Dock/notification).
        // Hiding behavior still respects `enableHideOnInactivity` inside the handler.
        startInactivityMonitoring()
    }

    func show(animated: Bool = false) {
        guard var s = state else { return }

        // Mark visible first
        s.isHidden = false
        state = s

        // Activate/raise first (some apps ignore AX position changes while not active)
        raiseAndActivateWindow()

        // Then move window back on-screen
        moveWindow(s.axWindow, to: s.lastVisibleFrame.origin, animated: animated)

        startCursorMonitoring()
        startFrameSync()

        // Always monitor app activation while docked (needed to reveal on Dock/notification).
        // Hiding behavior still respects `enableHideOnInactivity` inside the handler.
        startInactivityMonitoring()
    }

    func hide(animated: Bool = false) {
        guard var s = state else { return }

        // Capture the current visible frame before hiding (handles manual move/resize)
        if let current = getFrame(s.axWindow) {
            s.lastVisibleFrame = current
            // If the window moved to another screen, update screen frame too
            if let sc = screenForPoint(CGPoint(x: current.midX, y: current.midY)) {
                s.screenFrame = sc.frame
            }
        }

        let hiddenOrigin = hiddenOrigin(for: s)
        moveWindow(s.axWindow, to: hiddenOrigin, animated: animated)
        s.isHidden = true
        state = s

        stopFrameSync()
        stopCursorMonitoring()
        // Keep app-activation monitoring running even while hidden so we can reveal on Dock/notification.
        // stopInactivityMonitoring() is called only on restore/deinit.
    }

    // MARK: - Public helpers

    func restoreAndClear() {
        guard let s = state else { return }
        // Stop any monitoring first
        stopFrameSync()
        stopCursorMonitoring()
        stopInactivityMonitoring()

        // Restore to last visible position
        moveWindow(s.axWindow, to: s.lastVisibleFrame.origin, animated: false)

        state = nil
    }

    func currentFrame() -> CGRect? {
        guard let s = state else { return nil }
        return getFrame(s.axWindow) ?? s.lastVisibleFrame
    }

    // MARK: - Cursor leave hide

    private func startCursorMonitoring() {
        stopCursorMonitoring()

        // Initialize state
        lastMouseInside = isMouseOverTargetWindow()
        hasEnteredTargetSinceShow = lastMouseInside
        // NOTE: do not schedule hide immediately here; we only start hiding after the user has actually entered the window.

        // Only need global mouse move events to detect enter/exit.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            self?.handleGlobalMouseMove()
        }) {
            globalMonitors.append(m)
        }
    }

    private func stopCursorMonitoring() {
        cursorLeaveTimer?.invalidate()
        cursorLeaveTimer = nil

        for m in globalMonitors {
            NSEvent.removeMonitor(m)
        }
        globalMonitors.removeAll()
    }

    private func handleGlobalMouseMove() {
        guard state != nil else { return }

        let inside = isMouseOverTargetWindow()

        if inside {
            hasEnteredTargetSinceShow = true
        }

        // Transition: inside -> outside
        if lastMouseInside && !inside {
            // Only hide-on-leave after the user has actually been inside the window
            if hasEnteredTargetSinceShow {
                scheduleHideAfterCursorLeave()
            }
        }

        // Transition: outside -> inside
        if !lastMouseInside && inside {
            cancelHideAfterCursorLeave()
        }

        lastMouseInside = inside
    }

    private func scheduleHideAfterCursorLeave() {
        guard let cfg = state?.settings, cfg.enableHideOnCursorLeave else { return }

        cursorLeaveTimer?.invalidate()
        cursorLeaveTimer = Timer.scheduledTimer(withTimeInterval: cfg.cursorLeaveHideDelay, repeats: false) { [weak self] _ in
            guard let self else { return }

            // Re-check before hiding: if cursor returned to the window, do nothing.
            if self.isMouseOverTargetWindow() {
                self.cancelHideAfterCursorLeave()
                return
            }

            self.hide(animated: true)
        }
    }

    private func cancelHideAfterCursorLeave() {
        cursorLeaveTimer?.invalidate()
        cursorLeaveTimer = nil
    }

    // MARK: - Inactivity hide

    func startInactivityMonitoring() {
        if !workspaceObservers.isEmpty { return }
        stopInactivityMonitoring()

        lastActivatedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            self?.handleActiveAppChanged(notification)
        }
        workspaceObservers.append(observer)

        let terminateObserver = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            self?.handleAppTerminated(notification)
        }
        workspaceObservers.append(terminateObserver)
    }

    func stopInactivityMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        cancelInactivityHide()
    }

    private func handleActiveAppChanged(_ notification: Notification) {
        guard let s = state else { return }
        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        // If the docked app becomes active, cancel any pending hide and reveal if currently hidden.
        if app.processIdentifier == s.ownerPID {
            cancelInactivityHide()

            if s.isHidden {
                if shouldSuppressRevealAfterTermination() {
                    lastActivatedPID = app.processIdentifier
                    return
                }

                // Small delay helps apps that reposition/raise their windows right after activation (e.g. notification click).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.show(animated: true)
                }
            }
            lastActivatedPID = app.processIdentifier
            return
        }

        // If disabled, don't schedule inactivity hiding.
        if !s.settings.enableHideOnInactivity {
            cancelInactivityHide()
            return
        }

        // If the docked window is already hidden, no need to schedule inactivity hiding.
        if s.isHidden {
            cancelInactivityHide()
            return
        }

        // If cursor is on the window, don't hide due to inactivity.
        if isMouseOverTargetWindow() {
            cancelInactivityHide()
            return
        }

        scheduleInactivityHide()
        lastActivatedPID = app.processIdentifier
    }

    private func handleAppTerminated(_ notification: Notification) {
        guard let s = state else { return }
        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        lastTerminationPID = app.processIdentifier
        lastTerminationAt = Date()
    }

    private func shouldSuppressRevealAfterTermination() -> Bool {
        guard let lastTerminationPID, let lastTerminationAt else { return false }
        guard let ownerPID = state?.ownerPID, lastTerminationPID != ownerPID else { return false }
        return Date().timeIntervalSince(lastTerminationAt) < 1.5
    }

    private func scheduleInactivityHide() {
        guard let cfg = state?.settings else { return }
        cancelInactivityHide()
        inactiveHideTimer = Timer.scheduledTimer(withTimeInterval: cfg.inactivityHideDelay, repeats: false) { [weak self] _ in
            self?.hide(animated: true)
        }
    }

    private func cancelInactivityHide() {
        inactiveHideTimer?.invalidate()
        inactiveHideTimer = nil
    }

    // MARK: - Helpers

    private func startFrameSync() {
        stopFrameSync()
        frameSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.syncFrameIfNeeded()
        }
    }

    private func stopFrameSync() {
        frameSyncTimer?.invalidate()
        frameSyncTimer = nil
    }

    private func syncFrameIfNeeded() {
        guard var s = state, !s.isHidden, !isAnimatingMove else { return }
        guard let current = getFrame(s.axWindow) else { return }

        // Ignore tiny jitters
        let changed =
            abs(current.origin.x - s.lastVisibleFrame.origin.x) > 0.5 ||
            abs(current.origin.y - s.lastVisibleFrame.origin.y) > 0.5 ||
            abs(current.size.width - s.lastVisibleFrame.size.width) > 0.5 ||
            abs(current.size.height - s.lastVisibleFrame.size.height) > 0.5

        guard changed else { return }

        s.lastVisibleFrame = current
        if let sc = screenForPoint(CGPoint(x: current.midX, y: current.midY)) {
            s.screenFrame = sc.frame
        }
        state = s
    }

    private func raiseAndActivateWindow() {
        guard let s = state else { return }

        if let app = NSRunningApplication(processIdentifier: s.ownerPID) {
            app.activate()
        }

        // Ask the target window to raise above other windows
        AXUIElementPerformAction(s.axWindow, kAXRaiseAction as CFString)
    }

    private func isMouseOverTargetWindow() -> Bool {
        guard let st = state, let raw = getFrame(st.axWindow) else { return false }

        let mouse = NSEvent.mouseLocation

        // 1) Немного расширяем рамку (тени/скругления/особенности рендера)
        let padding: CGFloat = 10
        func expanded(_ r: CGRect) -> CGRect { r.insetBy(dx: -padding, dy: -padding) }

        let f1 = expanded(raw)
        if f1.contains(mouse) { return true }

        // 2) На некоторых конфигурациях AX-координаты могут быть по Y "перевёрнуты".
        // Пробуем флипнуть Y относительно screenFrame.
        let flippedY = st.screenFrame.maxY - raw.origin.y - raw.size.height
        let flipped = CGRect(x: raw.origin.x, y: flippedY, width: raw.size.width, height: raw.size.height)

        let f2 = expanded(flipped)
        if f2.contains(mouse) { return true }

        return false
    }

    private func hiddenOrigin(for s: DockState) -> CGPoint {
        let w = s.lastVisibleFrame.width
        let y = s.lastVisibleFrame.minY
        switch s.side {
        case .right:
            // оставляем grip пикселей видимыми
            return CGPoint(x: s.screenFrame.maxX - s.grip, y: y)
        case .left:
            return CGPoint(x: s.screenFrame.minX - (w - s.grip), y: y)
        }
    }

    private func getFrame(_ axWindow: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
            AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let posCF = posRef,
            let sizeCF = sizeRef
        else { return nil }

        var p = CGPoint.zero
        var s = CGSize.zero
        AXValueGetValue(posCF as! AXValue, .cgPoint, &p)
        AXValueGetValue(sizeCF as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private func screenForPoint(_ p: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(p) }
    }

    private func setPosition(_ axWindow: AXUIElement, _ p: CGPoint) {
        var point = p
        guard let axVal = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, axVal)
    }

    private func moveWindow(_ axWindow: AXUIElement, to dest: CGPoint, animated: Bool) {
        if !animated {
            setPosition(axWindow, dest)
            return
        }

        // “мягкая” анимация шагами (опционально)
        guard let frame = getFrame(axWindow) else { setPosition(axWindow, dest); return }
        let start = frame.origin
        let steps = 14
        let duration: TimeInterval = 0.20
        let interval = duration / Double(steps)
        isAnimatingMove = true

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = start.x + (dest.x - start.x) * t
            let y = start.y + (dest.y - start.y) * t
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                self.setPosition(axWindow, CGPoint(x: x, y: y))
                if i == steps {
                    self.isAnimatingMove = false
                }
            }
        }
    }

    deinit {
        // Ensure the target window is not left hidden off-screen
        if let s = state {
            stopFrameSync()
            stopCursorMonitoring()
            stopInactivityMonitoring()
            moveWindow(s.axWindow, to: s.lastVisibleFrame.origin, animated: false)
        } else {
            stopFrameSync()
            stopCursorMonitoring()
            stopInactivityMonitoring()
        }
    }
}
