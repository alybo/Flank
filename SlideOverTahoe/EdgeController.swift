import Cocoa

final class EdgeController {
    let side: DockState.Side
    let manager = SlideOverManager()
    let overlay = EdgeOverlayController()

    private var revealWorkItem: DispatchWorkItem?
    private var lastSettings = EdgeSettings()
    private var workspaceObservers: [NSObjectProtocol] = []

    init(side: DockState.Side) {
        self.side = side

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.apply(settings: self.lastSettings)
            }
        )
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.apply(settings: self.lastSettings)
            }
        )
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for o in workspaceObservers { center.removeObserver(o) }
    }

    func apply(settings: EdgeSettings) {
        lastSettings = settings

        // Edge globally disabled → fully restore and do nothing
        if settings.isEnabled == false {
            overlay.hide()
            if manager.state != nil { manager.restoreAndClear() }
            return
        }

        // Nothing selected → disable this edge
        if settings.selectedBundleID == nil && settings.selectedPID == nil {
            overlay.hide()
            if manager.state != nil { manager.restoreAndClear() }
            return
        }

        var effective = settings

        // Migration: if bundleID is missing but legacy PID exists, try to resolve bundleID
        if effective.selectedBundleID == nil, let legacyPID = effective.selectedPID {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid_t(legacyPID) }),
               let bid = app.bundleIdentifier {
                effective.selectedBundleID = bid
                effective.selectedPID = nil

                // Persist migration
                if side == .left {
                    SettingsStore.shared.left = effective
                } else {
                    SettingsStore.shared.right = effective
                }
            }
        }

        guard let bundleID = effective.selectedBundleID else {
            overlay.hide()
            if manager.state != nil { manager.restoreAndClear() }
            return
        }

        // Find running app by bundleID
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            // App not running yet → keep settings and wait
            overlay.hide()
            if manager.state != nil { manager.restoreAndClear() }
            return
        }

        let pid = app.processIdentifier
        let gripWidth = max(1, effective.gripWidth)
        let overlayWidth = max(2, effective.overlayWidth)

        // If the same app/window is already docked on this edge, just update settings.
        if let st = manager.state, st.ownerPID == pid {
            manager.updateSettings(effective)
            overlay.onEnter = { [weak self] in
                self?.scheduleReveal(delay: effective.revealDelay)
            }
            let frame = manager.currentFrame() ?? NSScreen.main?.frame ?? .zero
            let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) } ?? NSScreen.main!
            overlay.showOnScreen(side: side, screen: screen, width: CGFloat(overlayWidth))
            return
        }

        // Resolve AX window (focused or first)
        guard let axWindow = AXWindowResolver.resolveFocusedOrFirstWindow(pid: pid) else {
            overlay.hide()
            if manager.state != nil { manager.restoreAndClear() }
            return
        }

        manager.dock(axWindow: axWindow, ownerPID: pid, side: side, grip: CGFloat(gripWidth), settings: effective)

        // Place overlay on the screen where the window is
        let frame = manager.currentFrame() ?? NSScreen.main?.frame ?? .zero
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) } ?? NSScreen.main!

        overlay.onEnter = { [weak self] in
            self?.scheduleReveal(delay: effective.revealDelay)
        }

        overlay.showOnScreen(side: side, screen: screen, width: CGFloat(overlayWidth))
    }

    private func scheduleReveal(delay: TimeInterval) {
        revealWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.manager.show(animated: true)
        }
        revealWorkItem = work

        let d = max(0, delay)
        if d == 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: work)
        }
    }
}
