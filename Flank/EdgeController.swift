import Cocoa
import Combine
import ApplicationServices

final class EdgeController: ObservableObject {
    var side: DockState.Side { lastSettings.side }
    let manager = FlankManager()
    let overlay = EdgeOverlayController()
    let indicator = EdgeRevealIndicatorController()
    @Published private(set) var selectedWindow: SelectableWindow?
    @Published private(set) var selectionMessage: String?
    @Published private(set) var canUndo = false

    private let revealDelay = CancellableDelay()
    private let undoExpiry = CancellableDelay()
    private let lifecycle = WindowLifecycleMonitor()
    private let feedback = SelectionFeedbackController()
    private var stateSubscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var lastSettings = EdgeSettings()
    private var observedSession: UUID?
    private var gestureActive = false
    private var undoRecord: (session: UUID, previous: SelectableWindow?, state: DockState?)?

    init() {
        overlay.onExit = { [weak self] in self?.revealDelay.cancel() }
        stateSubscription = manager.$state.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.syncState() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.revealDelay.cancel()
            self.indicator.hide()
            self.overlay.hide()
            self.invalidateUndo()
            if self.manager.state != nil {
                self.selectionMessage = "Изменились экраны. Верните окно и выберите его заново."
            }
        }
    }

    func apply(settings raw: EdgeSettings) {
        let settings = raw.validated()
        if settings != lastSettings { invalidateUndo() }
        lastSettings = settings
        revealDelay.cancel()
        indicator.hide()
        // A bundle ID saved by old versions never authorizes an arbitrary window.
        if manager.state == nil {
            if settings.selectedBundleID != nil || settings.selectedPID != nil {
                selectionMessage = "Выберите конкретное окно заново — прежние настройки сохраняли только приложение."
            }
            overlay.hide()
            return
        }
        if let current = manager.state, settings.isEnabled,
           settings.side != current.side || !current.settings.isEnabled {
            do {
                guard try WindowCatalog.contains(current.axWindow, pid: current.ownerPID) else {
                    throw WindowAccessError.accessibility(.invalidUIElement)
                }
                let fresh = try WindowCatalog.describe(current.axWindow, pid: current.ownerPID,
                    safeFrame: current.phase == .paused ? nil : current.lastVisibleFrame, side: settings.side)
                if let reason = fresh.unavailableReason {
                    lastSettings = current.settings
                    SettingsStore.shared.configuration = lastSettings
                    reportSelectionError(reason)
                    syncState()
                    return
                }
            } catch {
                lastSettings = current.settings
                SettingsStore.shared.configuration = lastSettings
                reportSelectionError(error.localizedDescription)
                syncState()
                return
            }
        }
        if !manager.updateSettings(settings), let retained = manager.state {
            lastSettings = retained.settings
            SettingsStore.shared.configuration = lastSettings
        } else { selectionMessage = nil }
        syncState()
    }

    @discardableResult
    func select(_ candidate: SelectableWindow, restoreFrame: CGRect? = nil) -> Bool {
        revealDelay.cancel()
        indicator.hide()
        invalidateUndo()
        let previous = selectedWindow
        let previousState = manager.state
        do {
            guard try WindowCatalog.contains(candidate.element, pid: candidate.pid) else {
                reportSelectionError("Окно уже закрыто. Обновите список и выберите другое.")
                return false
            }
            let fresh = try WindowCatalog.describe(candidate.element, pid: candidate.pid, id: candidate.id, safeFrame: restoreFrame, side: side)
            guard fresh.unavailableReason == nil else {
                reportSelectionError(fresh.unavailableReason)
                return false
            }
            var settings = lastSettings
            settings.isEnabled = true
            settings.selectedBundleID = nil
            settings.selectedPID = nil
            let result = manager.dock(axWindow: fresh.element, ownerPID: fresh.pid, side: side,
                                      grip: CGFloat(settings.gripWidth), settings: settings, restoreFrame: restoreFrame)
            if let bound = manager.state, CFEqual(bound.axWindow, fresh.element) {
                selectedWindow = fresh // Includes a failed move that still requires recovery.
                watch(bound)
            }
            guard result else {
                reportSelectionError(manager.lastError)
                syncState()
                return false
            }
            manager.hide()
            lastSettings = settings
            SettingsStore.shared.configuration = settings
            selectionMessage = nil
            syncState()
            if let state = manager.state {
                let same = previousState.map { CFEqual($0.axWindow, fresh.element) } ?? false
                undoRecord = (state.id, same ? nil : previous, same ? nil : previousState)
                canUndo = true
                undoExpiry.schedule(after: 8) { [weak self] in self?.invalidateUndo() }
                feedback.show("«\(fresh.displayTitle)» добавлено", screen: WindowGeometry.screen(forAX: state.lastVisibleFrame)) { [weak self] in
                    self?.undoSelection()
                }
            }
            return true
        } catch {
            reportSelectionError(error.localizedDescription)
            return false
        }
    }

    func undoSelection() {
        guard let undo = undoRecord, manager.state?.id == undo.session else { invalidateUndo(); return }
        // Keep the record if returning the new window fails, so the action can be retried.
        guard manager.restoreAndClear() else { reportSelectionError(manager.lastError); return }
        invalidateUndo()
        selectedWindow = nil
        if let previous = undo.previous, let oldState = undo.state,
           (try? WindowCatalog.contains(previous.element, pid: previous.pid)) == true {
            guard let fresh = try? WindowCatalog.describe(previous.element, pid: previous.pid, side: oldState.side), fresh.unavailableReason == nil else {
                reportSelectionError("Новое окно возвращено. Прежнее окно больше недоступно для Flank — выберите его заново.")
                syncState()
                return
            }
            let restored = manager.dock(axWindow: previous.element, ownerPID: previous.pid, side: oldState.side,
                                         grip: oldState.grip, settings: oldState.settings)
            if let bound = manager.state {
                selectedWindow = previous
                watch(bound)
            }
            if restored {
                lastSettings = oldState.settings
                SettingsStore.shared.configuration = lastSettings
            }
            selectionMessage = restored ? nil : manager.lastError
        }
        syncState()
    }

    func setHidingEnabled(_ enabled: Bool) {
        var settings = lastSettings
        settings.isEnabled = enabled
        settings.selectedBundleID = nil
        settings.selectedPID = nil
        apply(settings: settings)
        SettingsStore.shared.configuration = lastSettings
    }

    @discardableResult
    func detach(session: UUID? = nil, restoreFrame: CGRect? = nil) -> Bool {
        if let session, manager.state?.id != session { return false }
        invalidateUndo()
        revealDelay.cancel()
        overlay.hide()
        indicator.hide()
        guard manager.restoreAndClear(restoreFrame: restoreFrame, session: session) else {
            reportSelectionError(manager.lastError)
            syncState()
            return false
        }
        selectionMessage = nil
        lastSettings.selectedBundleID = nil
        lastSettings.selectedPID = nil
        SettingsStore.shared.configuration = lastSettings
        syncState()
        return true
    }

    func setGestureActive(_ active: Bool) {
        gestureActive = active
        manager.suspendInteraction(active)
        revealDelay.cancel()
        indicator.hide()
        if active { overlay.hide() }
        else { configureOverlay() }
    }

    private func watch(_ state: DockState) {
        guard observedSession != state.id else { return }
        observedSession = state.id
        lifecycle.onClosed = { [weak self] in
            guard let self, self.manager.state?.id == state.id else { return }
            self.manager.clearClosedWindow(session: state.id)
            self.selectionMessage = "Выбранное окно закрыто. Выберите новое."
            self.syncState()
        }
        lifecycle.onRefresh = { [weak self] in
            guard let self, let current = self.manager.state, current.id == state.id,
                  let selected = self.selectedWindow else { return }
            if let title = (try? WindowCatalog.attribute(current.axWindow, kAXTitleAttribute)) as? String,
               title != selected.title {
                self.selectedWindow = SelectableWindow(id: selected.id, element: selected.element, pid: selected.pid,
                    appName: selected.appName, title: title, frame: selected.frame,
                    screenName: selected.screenName, unavailableReason: selected.unavailableReason)
            }
        }
        lifecycle.watch(state.axWindow, pid: state.ownerPID)
    }

    private func syncState() {
        guard let current = manager.state else {
            lifecycle.stop()
            observedSession = nil
            selectedWindow = nil
            invalidateUndo()
            overlay.hide()
            indicator.hide()
            revealDelay.cancel()
            return
        }
        if !current.canReveal { revealDelay.cancel(); indicator.hide() }
        if undoRecord != nil && current.phase != .hidden && current.phase != .unavailable { invalidateUndo() }
        if current.phase == .unavailable { overlay.hide(); return }
        configureOverlay()
    }

    private func configureOverlay() {
        guard !gestureActive, lastSettings.isEnabled, let current = manager.state,
              current.phase != .unavailable,
              let screen = WindowGeometry.screen(forAX: current.lastVisibleFrame),
              WindowGeometry.edgeIsExternal(screen.frame, side: side, among: NSScreen.screens.map(\.frame)) else {
            overlay.hide()
            return
        }
        overlay.onEnter = { [weak self] in self?.handleEdgeEnter(screen: screen) }
        overlay.showOnScreen(side: side, screen: screen, width: CGFloat(lastSettings.overlayWidth))
    }

    private func handleEdgeEnter(screen: NSScreen) {
        guard !gestureActive, let state = manager.state, state.canReveal else { return }
        let settings = lastSettings
        if settings.enableRevealIndicator {
            indicator.onActivate = { [weak self] in
                guard let self, !self.gestureActive, self.manager.state?.id == state.id,
                      self.manager.state?.canReveal == true else { return }
                self.indicator.hide()
                self.manager.show(animated: true)
            }
            indicator.show(side: side, screen: screen, edgeWidth: CGFloat(settings.overlayWidth))
        } else {
            revealDelay.schedule(after: settings.revealDelay) { [weak self] in
                guard let self, !self.gestureActive, self.lastSettings.isEnabled, self.overlay.isPointerInside,
                      self.manager.state?.id == state.id, self.manager.state?.canReveal == true else { return }
                self.manager.show(animated: true)
            }
        }
    }

    private func invalidateUndo() {
        let hadUndo = undoRecord != nil
        undoExpiry.cancel()
        undoRecord = nil
        canUndo = false
        if hadUndo { feedback.hide() }
    }

    private func reportSelectionError(_ message: String?) {
        selectionMessage = message
        if let message { feedback.show(message, screen: nil) }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        lifecycle.stop()
    }
}
