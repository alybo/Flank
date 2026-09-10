import ApplicationServices
import Cocoa
import Combine

struct DockState {
    let id = UUID()
    let axWindow: AXUIElement
    let ownerPID: pid_t
    var lastVisibleFrame: CGRect // AX coordinates; never replaced by an animation frame.
    var screenFrame: CGRect // AppKit coordinates.
    var side: Side
    var settings: EdgeSettings
    var phase: Phase = .visible

    var grip: CGFloat { CGFloat(settings.gripWidth) }
    var isHidden: Bool { phase == .hidden }
    var canReveal: Bool { phase == .hidden || phase == .hiding }
    nonisolated enum Side: String, Codable, CaseIterable {
        case left, right
        var label: String { self == .left ? "Слева" : "Справа" }
    }
    nonisolated enum Phase { case visible, hiding, hidden, showing, restoring, paused, unavailable }
}

final class FlankManager: ObservableObject {
    @Published private(set) var state: DockState?
    @Published private(set) var lastError: String?

    private let access: any WindowAccessing
    private let activePID: () -> pid_t?
    private let mouseLocation: () -> CGPoint
    private let screenFrameForWindow: (CGRect) -> CGRect?
    private let screenFrames: () -> [CGRect]
    private var cursorLeaveTimer: Timer?
    private var inactiveHideTimer: Timer?
    private var frameSyncTimer: Timer?
    private var animationTimer: Timer?
    private var activationReveal = CancellableDelay()
    private var mouseMonitors: [Any] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastMouseInside = false
    private var hasEnteredTargetSinceShow = false
    private var lastTerminationAt: Date?
    private var interactionSuspended = false

    init(access: any WindowAccessing = AXWindowAccess(),
         activePID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         screenFrameForWindow: @escaping (CGRect) -> CGRect? = { WindowGeometry.screen(forAX: $0)?.frame },
         screenFrames: @escaping () -> [CGRect] = { NSScreen.screens.map(\.frame) }) {
        self.access = access
        self.activePID = activePID
        self.mouseLocation = mouseLocation
        self.screenFrameForWindow = screenFrameForWindow
        self.screenFrames = screenFrames
        FlankManagerRegistry.shared.register(self)
    }

    @discardableResult
    func dock(axWindow: AXUIElement, ownerPID: pid_t, side: DockState.Side,
              grip: CGFloat = 4, settings: EdgeSettings, restoreFrame: CGRect? = nil) -> Bool {
        if let frame = restoreFrame,
           !frame.minX.isFinite || !frame.minY.isFinite || !frame.width.isFinite || !frame.height.isFinite || frame.width <= 0 || frame.height <= 0 {
            lastError = WindowAccessError.invalidGeometry.localizedDescription
            return false
        }
        var config = settings.validated()
        config.side = side
        config.gripWidth = Double(grip)
        config = config.validated()
        if let current = state, CFEqual(current.axWindow, axWindow), current.ownerPID == ownerPID {
            guard updateSettings(config) else { return false }
            if let restoreFrame, state != nil, config.isEnabled {
                state?.lastVisibleFrame = restoreFrame
                state?.screenFrame = screenFrameForWindow(restoreFrame) ?? current.screenFrame
                if let latest = state { move(to: hiddenOrigin(for: latest), animated: false, finalPhase: .hidden) }
            }
            return state != nil && state?.phase != .unavailable
        }
        // A failed restore keeps the previous window owned and recoverable.
        guard restoreAndClear() else { return false }
        do {
            let actualFrame = try access.frame(of: axWindow)
            let frame = restoreFrame ?? actualFrame
            state = DockState(axWindow: axWindow, ownerPID: ownerPID, lastVisibleFrame: frame,
                              screenFrame: screenFrameForWindow(frame) ?? .zero,
                              side: side, settings: config)
            lastTerminationAt = nil
            lastError = nil
            startInactivityMonitoring()
            if config.isEnabled, let latest = state {
                move(to: hiddenOrigin(for: latest), animated: false, finalPhase: .hidden)
            } else { state?.phase = .paused }
            return state?.phase == (config.isEnabled ? .hidden : .paused)
        } catch {
            recordFailure(error)
            return false
        }
    }

    @discardableResult
    func updateSettings(_ settings: EdgeSettings) -> Bool {
        guard let current = state else { return true }
        let updated = settings.validated()
        activationReveal.cancel()
        cancelHideTimers()
        let sideChanged = current.side != updated.side
        if !updated.isEnabled || sideChanged || (!current.settings.isEnabled && current.phase == .unavailable) {
            // Restore on the old side first. Failure retains the old side and recovery frame.
            guard pause() else { return false }
        }
        if updated.isEnabled, state?.phase == .paused {
            guard captureVisibleFrame(), let latest = state else { return false }
            guard WindowGeometry.edgeIsExternal(latest.screenFrame, side: updated.side, among: screenFrames()) else {
                lastError = "На выбранной стороне находится другой экран. Выберите внешний край."
                return false
            }
            state?.side = updated.side
            state?.settings = updated
            startInactivityMonitoring()
            if let latest = state { move(to: hiddenOrigin(for: latest), animated: false, finalPhase: .hidden) }
            return state?.phase == .hidden
        }
        state?.side = updated.side
        state?.settings = updated
        if current.settings.gripWidth != updated.gripWidth,
           let latest = state, latest.phase == .hidden || latest.phase == .hiding {
            move(to: hiddenOrigin(for: latest), animated: false, finalPhase: .hidden)
        }
        if state?.phase == .visible {
            refreshMouseMonitoring()
            reevaluateHiding()
        }
        return state?.phase != .unavailable
    }

    @discardableResult
    func pause() -> Bool {
        cancelAllWork()
        guard let current = state else { return true }
        state?.settings.isEnabled = false
        if current.phase == .paused {
            lastError = nil
            startInactivityMonitoring()
            return true
        }
        if current.phase == .visible && !captureVisibleFrame() { return false }
        guard let latest = state else { return true }
        state?.phase = .restoring
        do {
            try access.setPosition(of: latest.axWindow, to: latest.lastVisibleFrame.origin)
            try verifyPosition(latest.axWindow, at: latest.lastVisibleFrame.origin)
            state?.phase = .paused
            lastError = nil
            startInactivityMonitoring() // Keep observing owner termination while paused.
            return true
        } catch { recordFailure(error); return false }
    }

    func show(animated: Bool = false) {
        guard !interactionSuspended else { return }
        activationReveal.cancel()
        cancelHideTimers()
        guard let current = state, current.settings.isEnabled,
              current.phase != .showing, current.phase != .visible,
              current.phase != .restoring, current.phase != .unavailable else { return }
        // Activate the owner, then attempt to raise this exact window. Unsupported raise
        // must not prevent a verified return; other failures still retain recovery data.
        NSRunningApplication(processIdentifier: current.ownerPID)?.activate()
        do {
            try access.raise(current.axWindow)
        } catch let error as WindowAccessError where error.isUnsupportedRaise {
            // No focused/first-window fallback: only move the currently bound AX element.
        } catch { recordFailure(error); return }
        move(to: current.lastVisibleFrame.origin, animated: animated, finalPhase: .visible)
    }

    func hide(animated: Bool = false) {
        guard !interactionSuspended else { return }
        activationReveal.cancel()
        cancelHideTimers()
        guard let current = state, current.settings.isEnabled,
              current.phase == .visible || current.phase == .showing else { return }
        // Only a stable visible frame is a valid restore destination.
        if current.phase == .visible && !captureVisibleFrame() { return }
        guard let latest = state else { return }
        move(to: hiddenOrigin(for: latest), animated: animated, finalPhase: .hidden)
    }

    @discardableResult
    func restoreAndClear(restoreFrame: CGRect? = nil, session: UUID? = nil) -> Bool {
        if let session, state?.id != session { return false }
        if let frame = restoreFrame,
           !frame.minX.isFinite || !frame.minY.isFinite || !frame.width.isFinite || !frame.height.isFinite || frame.width <= 0 || frame.height <= 0 {
            lastError = WindowAccessError.invalidGeometry.localizedDescription
            return false
        }
        cancelAllWork()
        guard let current = state else {
            lastError = nil
            return true
        }
        if current.phase == .paused && restoreFrame == nil {
            state = nil
            lastError = nil
            return true
        }
        if restoreFrame == nil && current.phase == .visible && !captureVisibleFrame() { return false }
        if let restoreFrame { state?.lastVisibleFrame = restoreFrame }
        guard let latest = state else { return true }
        state?.phase = .restoring
        do {
            try access.setPosition(of: latest.axWindow, to: latest.lastVisibleFrame.origin)
            try verifyPosition(latest.axWindow, at: latest.lastVisibleFrame.origin)
            state = nil
            lastError = nil
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    func currentFrame() -> CGRect? {
        guard let current = state else { return nil }
        return try? access.frame(of: current.axWindow)
    }

    func suspendInteraction(_ suspended: Bool) {
        interactionSuspended = suspended
        activationReveal.cancel()
        stopVisibleMonitoring()
        if !suspended, state?.phase == .visible, captureVisibleFrame() { startVisibleMonitoring() }
    }

    // Called only after confirmed destruction/absence of this exact session's window.
    func clearClosedWindow(session: UUID) {
        guard state?.id == session else { return }
        cancelAllWork()
        state = nil
        lastError = nil
    }

    // MARK: Movement

    private func move(to destination: CGPoint, animated: Bool, finalPhase: DockState.Phase) {
        cancelMovement()
        stopVisibleMonitoring()
        guard let current = state else { return }
        state?.phase = finalPhase == .hidden ? .hiding : .showing
        lastError = nil
        do {
            if !animated {
                try finishMove(window: current.axWindow, destination: destination, phase: finalPhase)
                return
            }
            let start = try access.position(of: current.axWindow)
            let started = ProcessInfo.processInfo.systemUptime
            let session = current.id
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self, self.animationTimer === timer, self.state?.id == session else {
                    timer.invalidate()
                    return
                }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / 0.20)
                do {
                    if progress >= 1 {
                        self.cancelMovement()
                        try self.finishMove(window: current.axWindow, destination: destination, phase: finalPhase)
                    } else {
                        let fraction = CGFloat(progress)
                        let point = CGPoint(x: start.x + (destination.x - start.x) * fraction,
                                            y: start.y + (destination.y - start.y) * fraction)
                        try self.access.setPosition(of: current.axWindow, to: point)
                    }
                } catch { self.recordFailure(error) }
            }
            animationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch { recordFailure(error) }
    }

    private func finishMove(window: AXUIElement, destination: CGPoint, phase: DockState.Phase) throws {
        try access.setPosition(of: window, to: destination)
        try verifyPosition(window, at: destination)
        state?.phase = phase
        if phase == .visible {
            startVisibleMonitoring()
        }
    }

    private func verifyPosition(_ window: AXUIElement, at point: CGPoint) throws {
        let actual = try access.position(of: window)
        guard abs(actual.x - point.x) <= 1, abs(actual.y - point.y) <= 1 else {
            throw WindowAccessError.positionNotApplied
        }
    }

    private func cancelMovement() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func hiddenOrigin(for current: DockState) -> CGPoint {
        let x = current.side == .right
            ? current.screenFrame.maxX - current.grip
            : current.screenFrame.minX - current.lastVisibleFrame.width + current.grip
        return CGPoint(x: x, y: current.lastVisibleFrame.minY)
    }

    @discardableResult
    private func captureVisibleFrame() -> Bool {
        guard var current = state, current.phase == .visible || current.phase == .paused else { return true }
        do {
            let frame = try access.frame(of: current.axWindow)
            let screenFrame = screenFrameForWindow(frame) ?? current.screenFrame
            guard frame != current.lastVisibleFrame || screenFrame != current.screenFrame else { return true }
            current.lastVisibleFrame = frame
            current.screenFrame = screenFrame
            state = current
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    private func recordFailure(_ error: Error) {
        cancelMovement()
        stopVisibleMonitoring()
        activationReveal.cancel()
        state?.phase = .unavailable
        lastError = error.localizedDescription
        // Even after a failed restore/disable, observe the owner's termination.
        if state != nil { startInactivityMonitoring() }
    }

    // MARK: Cursor and inactivity

    private func startVisibleMonitoring() {
        guard !interactionSuspended else { return }
        lastMouseInside = isMouseOverTargetWindow()
        hasEnteredTargetSinceShow = lastMouseInside
        refreshMouseMonitoring()
        frameSyncTimer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self, self.state?.phase == .visible else { return }
            if self.captureVisibleFrame() { self.handleMouseMove() }
        }
        frameSyncTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        reevaluateHiding()
    }

    private func refreshMouseMonitoring() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        guard !interactionSuspended, let config = state?.settings,
              config.enableHideOnCursorLeave || config.enableHideOnInactivity else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.handleMouseMove()
        }) { mouseMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleMouseMove()
            return event
        }) { mouseMonitors.append(monitor) }
    }

    private func stopVisibleMonitoring() {
        frameSyncTimer?.invalidate()
        frameSyncTimer = nil
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        cancelHideTimers()
    }

    private func handleMouseMove() {
        guard state?.phase == .visible else { return }
        let inside = isMouseOverTargetWindow()
        if inside { hasEnteredTargetSinceShow = true }
        if inside != lastMouseInside {
            lastMouseInside = inside
            reevaluateHiding()
        }
    }

    // No synchronous AX calls on the mouse event hot path.
    private func isMouseOverTargetWindow() -> Bool {
        guard let current = state else { return false }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? current.screenFrame.maxY
        let frame = WindowGeometry.appKitFrame(fromAX: current.lastVisibleFrame, primaryMaxY: primaryMaxY)
        return frame.insetBy(dx: -10, dy: -10).contains(mouseLocation())
    }

    private func reevaluateHiding() {
        guard !interactionSuspended, let current = state, current.phase == .visible, current.settings.isEnabled else {
            cancelHideTimers()
            return
        }
        if isMouseOverTargetWindow() {
            cancelHideTimers()
            return
        }
        if current.settings.enableHideOnCursorLeave && hasEnteredTargetSinceShow {
            if cursorLeaveTimer == nil {
                cursorLeaveTimer = hideTimer(delay: current.settings.cursorLeaveHideDelay, session: current.id, cursor: true)
            }
        } else {
            cursorLeaveTimer?.invalidate()
            cursorLeaveTimer = nil
        }
        if current.settings.enableHideOnInactivity,
           let active = activePID(), active != current.ownerPID {
            if inactiveHideTimer == nil {
                inactiveHideTimer = hideTimer(delay: current.settings.inactivityHideDelay, session: current.id, cursor: false)
            }
        } else {
            inactiveHideTimer?.invalidate()
            inactiveHideTimer = nil
        }
    }

    private func hideTimer(delay: TimeInterval, session: UUID, cursor: Bool) -> Timer {
        let timer = Timer(timeInterval: max(0.001, delay), repeats: false) { [weak self] timer in
            guard let self else { return }
            guard (cursor ? self.cursorLeaveTimer : self.inactiveHideTimer) === timer else { return }
            if cursor { self.cursorLeaveTimer = nil } else { self.inactiveHideTimer = nil }
            guard let current = self.state, current.id == session, current.phase == .visible,
                  current.settings.isEnabled, !self.isMouseOverTargetWindow() else { return }
            if cursor {
                guard current.settings.enableHideOnCursorLeave, self.hasEnteredTargetSinceShow else { return }
            } else {
                guard current.settings.enableHideOnInactivity,
                      let active = self.activePID(),
                      active != current.ownerPID else { return }
            }
            self.hide(animated: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func cancelHideTimers() {
        cursorLeaveTimer?.invalidate()
        cursorLeaveTimer = nil
        inactiveHideTimer?.invalidate()
        inactiveHideTimer = nil
    }

    func startInactivityMonitoring() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                      object: nil, queue: .main) { [weak self] notification in
            self?.handleActivation(notification)
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                      object: nil, queue: .main) { [weak self] notification in
            self?.handleTermination(notification)
        })
    }

    func stopInactivityMonitoring() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        activationReveal.cancel()
        cancelHideTimers()
    }

    private func handleActivation(_ notification: Notification) {
        activationReveal.cancel()
        guard !interactionSuspended else { return }
        guard let current = state, current.settings.isEnabled,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.processIdentifier == current.ownerPID {
            cancelHideTimers()
            guard current.canReveal else { return }
            if let lastTerminationAt, Date().timeIntervalSince(lastTerminationAt) < 1.5 { return }
            activationReveal.schedule(after: 0.12) { [weak self] in
                guard let self, self.state?.id == current.id,
                      self.activePID() == current.ownerPID else { return }
                self.show(animated: true)
            }
        } else {
            reevaluateHiding()
        }
    }

    private func handleTermination(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.processIdentifier == state?.ownerPID {
            // The process is gone, so there is no surviving window to recover.
            cancelAllWork()
            state = nil
            lastError = nil
        } else {
            lastTerminationAt = Date()
        }
    }

    private func cancelAllWork() {
        cancelMovement()
        stopVisibleMonitoring()
        stopInactivityMonitoring()
    }

    deinit {
        cancelAllWork()
        if let current = state, current.phase != .paused {
            try? access.setPosition(of: current.axWindow, to: current.lastVisibleFrame.origin)
        }
    }
}
