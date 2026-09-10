import ApplicationServices
import Cocoa

final class WindowDragCaptureController {
    private let edge: EdgeController
    private let target = WindowDropPanel()
    private let settle = CancellableDelay()
    private var monitors: [Any] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var settings = EdgeSettings()
    private var candidate: SelectableWindow?
    private var intent: WindowDragIntent?
    private var detachSession: UUID?
    private var screen: NSScreen?
    private var lastRead: TimeInterval = 0
    private var generation = UUID()
    private var watchdog: Timer?

    init(edge: EdgeController) {
        self.edge = edge
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.handle(event) }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.handle(event); return event }) {
            monitors.append(monitor)
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.cancel() })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let candidate = self.candidate,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != candidate.pid else { return }
            self.cancel()
        })
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in self?.cancel() }
    }

    func apply(settings: EdgeSettings) {
        if self.settings != settings { cancel() }
        self.settings = settings
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { cancel() }
            return // Never inspect, retain or log typed characters.
        }
        guard settings.enableDragToDock else { cancel(); return }
        switch event.type {
        case .leftMouseDown:
            cancel()
            let point = pointer(for: event)
            guard Accessibility.isTrusted(), let candidate = WindowCatalog.candidate(at: point, side: settings.side),
                  let screen = WindowGeometry.screen(forAX: candidate.frame) else { return }
            if let bound = edge.manager.state, CFEqual(bound.axWindow, candidate.element) {
                guard bound.phase == .visible || bound.phase == .paused else { return }
                detachSession = bound.id
            }
            self.candidate = candidate
            self.screen = screen
            intent = WindowDragIntent(initialFrame: candidate.frame, initialPointer: point, screenFrame: screen.frame)
            lastRead = 0
            edge.setGestureActive(true)
            startWatchdog()
        case .leftMouseDragged:
            update(event, force: false)
        case .flagsChanged:
            // Modifier releases after mouseUp must not cancel an already confirmed drop.
            if intent?.phase == .committing { return }
            update(event, force: true)
        case .leftMouseUp:
            update(event, force: true)
            let point = pointer(for: event)
            guard intent?.release(modifier: settings.dragModifier.matches(event.modifierFlags), insideTarget: target.frame?.contains(point) == true) == true else {
                cancel(); return
            }
            target.hide()
            guard let candidate else { cancel(); return }
            waitForSettlement(candidate: candidate, token: generation, previous: nil, attempts: 0)
        default: break
        }
    }

    private func update(_ event: NSEvent, force: Bool) {
        guard let candidate, let screen, intent?.phase != .committing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastRead >= 0.05 else { return }
        lastRead = now
        guard Accessibility.isTrusted(), let frame = try? AXWindowAccess().frame(of: candidate.element) else { cancel(); return }
        let point = pointer(for: event)
        intent?.update(frame: frame, pointer: point, modifier: settings.dragModifier.matches(event.modifierFlags),
                       insideTarget: target.frame?.contains(point) == true)
        guard let phase = intent?.phase, phase != .cancelled else { cancel(); return }
        if phase == .eligible || phase == .armed {
            target.show(screen: screen, armed: phase == .armed, replacing: edge.selectedWindow?.displayTitle,
                        side: settings.side, detaching: detachSession != nil)
        } else { target.hide() }
    }

    private func waitForSettlement(candidate: SelectableWindow, token: UUID, previous: CGRect?, attempts: Int) {
        settle.schedule(after: 0.06) { [weak self] in
            guard let self, self.generation == token, self.intent?.phase == .committing else { return }
            guard Accessibility.isTrusted(), let frame = try? AXWindowAccess().frame(of: candidate.element),
                  abs(frame.width - candidate.frame.width) <= 2, abs(frame.height - candidate.frame.height) <= 2 else {
                self.cancel(); return
            }
            if let previous, abs(previous.minX - frame.minX) <= 1, abs(previous.minY - frame.minY) <= 1 {
                if let session = self.detachSession {
                    _ = self.edge.detach(session: session, restoreFrame: candidate.frame)
                } else {
                    _ = self.edge.select(candidate, restoreFrame: candidate.frame)
                }
                self.finish()
            } else if attempts < 5 {
                self.waitForSettlement(candidate: candidate, token: token, previous: frame, attempts: attempts + 1)
            } else { self.cancel() }
        }
    }

    func cancel() { intent?.cancel(); finish() }

    private func pointer(for event: NSEvent) -> CGPoint {
        // Global monitors deliver asynchronously: use the release event's position.
        if let point = event.cgEvent?.location, let primary = NSScreen.screens.first {
            return CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        }
        return NSEvent.mouseLocation
    }

    private func startWatchdog() {
        let token = generation
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.generation == token else { return }
            guard Accessibility.isTrusted() else { self.cancel(); return }
            // Lost mouseUp must not leave normal reveal suspended indefinitely.
            if self.intent?.phase != .committing && NSEvent.pressedMouseButtons & 1 == 0 { self.cancel() }
        }
        watchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finish() {
        let wasActive = candidate != nil
        generation = UUID()
        settle.cancel()
        watchdog?.invalidate()
        watchdog = nil
        target.hide()
        candidate = nil
        intent = nil
        detachSession = nil
        screen = nil
        if wasActive { edge.setGestureActive(false) }
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        settle.cancel()
        watchdog?.invalidate()
        target.hide()
    }
}
