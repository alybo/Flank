// Audit harness: compiles the real manager against an in-memory AX boundary.
// No AX read/write request is sent to another application's window.
import Cocoa
import ApplicationServices

private var frames: [CFHashCode: CGRect] = [:]
private var rejectedWrites = Set<CFHashCode>()
private var ignoredWrites = Set<CFHashCode>()
private var malformedReads = Set<CFHashCode>()
private var rejectedRaises = Set<CFHashCode>()
private var raiseErrors: [CFHashCode: AXError] = [:]
private var unsupportedSizes = Set<CFHashCode>()
private var unsupportedPositions = Set<CFHashCode>()
private var writes: [CFHashCode: Int] = [:]
private var windowLists: [CFHashCode: CFTypeRef] = [:]

func AXUIElementCopyAttributeValue(_ element: AXUIElement, _ attribute: CFString,
                                  _ value: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
    if attribute as String == kAXWindowsAttribute {
        guard let list = windowLists[CFHash(element)] else { return .cannotComplete }
        value.pointee = list
        return .success
    }
    guard let frame = frames[CFHash(element)] else { return .invalidUIElement }
    if malformedReads.contains(CFHash(element)) {
        value.pointee = "not an AXValue" as CFString
        return .success
    }
    switch attribute as String {
    case kAXPositionAttribute:
        if unsupportedPositions.contains(CFHash(element)) { return .attributeUnsupported }
        var point = frame.origin
        value.pointee = AXValueCreate(.cgPoint, &point)
    case kAXSizeAttribute:
        if unsupportedSizes.contains(CFHash(element)) { return .attributeUnsupported }
        var size = frame.size
        value.pointee = AXValueCreate(.cgSize, &size)
    default: return .attributeUnsupported
    }
    return .success
}

@discardableResult
func AXUIElementSetAttributeValue(_ element: AXUIElement, _ attribute: CFString,
                                 _ value: CFTypeRef) -> AXError {
    let key = CFHash(element)
    writes[key, default: 0] += 1
    guard !rejectedWrites.contains(key) else { return .cannotComplete }
    if ignoredWrites.contains(key) { return .success }
    guard var frame = frames[key], attribute as String == kAXPositionAttribute else {
        return .invalidUIElement
    }
    var point = CGPoint.zero
    guard CFGetTypeID(value) == AXValueGetTypeID(),
          AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return .illegalArgument }
    frame.origin = point
    frames[key] = frame
    return .success
}

@discardableResult
func AXUIElementPerformAction(_ element: AXUIElement, _ action: CFString) -> AXError {
    raiseErrors[CFHash(element)] ?? (rejectedRaises.contains(CFHash(element)) ? .cannotComplete : .success)
}

private var nextPID: pid_t = 1_000_000_000
private var failures = 0
private var checks = 0
private let original = CGRect(x: 100, y: 100, width: 400, height: 300)

private final class WeakManager {
    weak var value: FlankManager?
    init(_ value: FlankManager?) { self.value = value }
}

private func makeWindow() -> (AXUIElement, pid_t) {
    nextPID += 1
    let element = AXUIElementCreateApplication(nextPID)
    frames[CFHash(element)] = original
    return (element, nextPID)
}

// Deterministic display topology: command-line harnesses may have no NSScreen.
private func makeManager(activePID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                         mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
                         screenFrames: @escaping () -> [CGRect] = { [CGRect(x: 0, y: 0, width: 1440, height: 900)] }) -> FlankManager {
    FlankManager(activePID: activePID, mouseLocation: mouseLocation,
        screenFrameForWindow: { _ in CGRect(x: 0, y: 0, width: 1440, height: 900) }, screenFrames: screenFrames)
}

private func dock(_ manager: FlankManager, settings: EdgeSettings = EdgeSettings()) -> AXUIElement {
    let (window, pid) = makeWindow()
    manager.dock(axWindow: window, ownerPID: pid, side: .right, settings: settings)
    return window
}

private func check(_ condition: Bool, _ name: String) {
    checks += 1
    if !condition { failures += 1 }
    print("\(condition ? "PASS" : "FAIL") \(name)")
}

private func drain(_ duration: TimeInterval = 0.30) {
    RunLoop.main.run(until: Date().addingTimeInterval(duration))
}

// Baseline: the mock exercises the actual production position writes.
@MainActor
private func runTests() throws {
    do {
        let manager = makeManager()
        let window = dock(manager)
        check(frames[CFHash(window)]!.origin != original.origin && writes[CFHash(window), default: 0] > 0,
              "baseline: dock writes an off-screen position")
        manager.restoreAndClear()
        check(frames[CFHash(window)] == original && manager.state == nil,
              "baseline: ordinary restore returns the original window")
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.hide()
        manager.restoreAndClear()
        check(frames[CFHash(window)] == original, "A01: repeated hide preserves restore position")
    }

    do {
        let manager = makeManager()
        let first = dock(manager)
        _ = dock(manager)
        check(frames[CFHash(first)] == original, "A02: replacing target restores the old window")
        manager.restoreAndClear()
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.show()
        manager.hide(animated: true)
        manager.restoreAndClear()
        drain()
        check(frames[CFHash(window)] == original, "A03: restore cancels queued hide animation")
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.show(animated: true)
        drain(0.06)
        manager.hide(animated: true)
        manager.restoreAndClear()
        drain()
        check(frames[CFHash(window)] == original, "A04: reversing animation preserves visible destination")
    }

    do {
        let manager = makeManager()
        let (window, pid) = makeWindow()
        rejectedWrites.insert(CFHash(window))
        manager.dock(axWindow: window, ownerPID: pid, side: .right, settings: EdgeSettings())
        check(manager.state?.isHidden != true, "A05: failed AX move must not report hidden")
        rejectedWrites.remove(CFHash(window))
        manager.restoreAndClear()
    }

    do {
        let manager = makeManager()
        _ = dock(manager)
        var updated = EdgeSettings()
        updated.gripWidth = 16
        manager.updateSettings(updated)
        check(manager.state?.grip == 16, "A06: changing grip updates actual docking geometry")
        manager.restoreAndClear()
    }

    do {
        let decoded = try JSONDecoder().decode(EdgeSettings.self, from: Data("{}".utf8))
        check(decoded == EdgeSettings(), "baseline: missing settings decode with defaults")
        let data = Data("{\"gripWidth\":-100,\"overlayWidth\":1000000,\"inactivityHideDelay\":-10}".utf8)
        let invalid = try JSONDecoder().decode(EdgeSettings.self, from: data)
        check((1...16).contains(invalid.gripWidth) && (2...20).contains(invalid.overlayWidth)
              && (0...20).contains(invalid.inactivityHideDelay), "A07: persisted settings validate numeric bounds")
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        rejectedWrites.insert(CFHash(window))
        manager.restoreAndClear()
        check(manager.state != nil, "A08: failed restore retains recovery information")
        rejectedWrites.remove(CFHash(window))
        manager.restoreAndClear()
    }

    // Synthetic activation only: no application is actually activated.
    do {
        let manager = makeManager(activePID: { NSRunningApplication.current.processIdentifier },
                                      mouseLocation: { CGPoint(x: -100_000, y: -100_000) })
        var settings = EdgeSettings()
        settings.inactivityHideDelay = 0.04
        let window = dock(manager, settings: settings)
        manager.show()
        // Ensure the actual cursor cannot intersect the fake target window.
        let mouse = NSEvent.mouseLocation
        frames[CFHash(window)] = CGRect(x: mouse.x + 100_000, y: mouse.y, width: 400, height: 300)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        settings.enableHideOnInactivity = false
        manager.updateSettings(settings)
        drain(0.12)
        check(manager.state?.isHidden == false, "A09: disabling inactivity cancels an already scheduled hide")
        manager.restoreAndClear()
    }

    do {
        let manager = makeManager()
        let first = dock(manager)
        let (second, pid) = makeWindow()
        rejectedWrites.insert(CFHash(first))
        let success = manager.dock(axWindow: second, ownerPID: pid, side: .right, settings: EdgeSettings())
        check(!success && manager.state.map { CFEqual($0.axWindow, first) } == true
              && frames[CFHash(second)] == original, "failed replacement keeps old target and leaves new window alone")
        rejectedWrites.remove(CFHash(first))
        check(manager.restoreAndClear() && frames[CFHash(first)] == original, "failed replacement can be recovered on retry")
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.show(animated: true)
        drain(0.05)
        rejectedWrites.insert(CFHash(window))
        drain(0.06)
        let attempts = writes[CFHash(window)]
        drain(0.25)
        check(manager.state?.phase == .unavailable && manager.lastError != nil
              && writes[CFHash(window)] == attempts, "AX error during animation stops further writes")
        rejectedWrites.remove(CFHash(window))
        check(manager.restoreAndClear() && frames[CFHash(window)] == original, "animation error preserves the safe restore position")
    }

    do {
        let manager = makeManager()
        let (window, pid) = makeWindow()
        ignoredWrites.insert(CFHash(window))
        manager.dock(axWindow: window, ownerPID: pid, side: .right, settings: EdgeSettings())
        check(manager.state?.phase == .unavailable && manager.lastError != nil,
              "AX success without actual movement is detected by readback")
        ignoredWrites.remove(CFHash(window))
        manager.restoreAndClear()
    }

    do {
        let manager = makeManager()
        let (window, pid) = makeWindow()
        malformedReads.insert(CFHash(window))
        manager.dock(axWindow: window, ownerPID: pid, side: .right, settings: EdgeSettings())
        check(manager.state == nil && manager.lastError != nil && frames[CFHash(window)] == original,
              "unexpected AX type is rejected without a crash or move")
        malformedReads.remove(CFHash(window))
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        rejectedRaises.insert(CFHash(window))
        manager.show()
        check(manager.state?.phase == .unavailable && manager.state?.lastVisibleFrame == original,
              "failed raise retains recovery information")
        rejectedRaises.remove(CFHash(window))
        manager.restoreAndClear()
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        let before = frames[CFHash(window)]!.minX
        var settings = EdgeSettings()
        settings.gripWidth = 16
        manager.updateSettings(settings)
        check(frames[CFHash(window)]!.minX == before - 12 && manager.state?.isHidden == true,
              "grip update immediately moves the hidden window")
        manager.show(animated: true)
        drain()
        check(manager.state?.phase == .visible && frames[CFHash(window)] == original,
              "completed reveal reaches the original position")
        manager.restoreAndClear()
    }

    do {
        let manager = makeManager()
        let first = dock(manager)
        manager.show()
        manager.hide(animated: true)
        var disabled = EdgeSettings()
        disabled.isEnabled = false
        manager.updateSettings(disabled)
        let second = dock(manager)
        let secondFrame = frames[CFHash(second)]
        drain()
        check(frames[CFHash(first)] == original && frames[CFHash(second)] == secondFrame,
              "disable during animation restores old window and cannot affect a new session")
        manager.restoreAndClear()
    }

    do {
        var manager: FlankManager? = makeManager()
        let window = dock(manager!)
        manager!.show(animated: true)
        let released = WeakManager(manager)
        manager = nil
        drain()
        check(released.value == nil && frames[CFHash(window)] == original,
              "animation does not retain manager or outlive its restore on deinit")
    }

    // Positive control for A09: inactivity does hide when enabled, then stops when disabled.
    do {
        var active: pid_t? = NSRunningApplication.current.processIdentifier
        var pointer = CGPoint(x: -100_000, y: -100_000)
        let manager = makeManager(activePID: { active }, mouseLocation: { pointer })
        var settings = EdgeSettings()
        settings.enableHideOnCursorLeave = false
        settings.inactivityHideDelay = 0.04
        let window = dock(manager, settings: settings)
        manager.show()
        drain(0.32)
        check(manager.state?.isHidden == true, "inactivity positive control: timer really hides when enabled")
        manager.show()
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? manager.state!.screenFrame.maxY
        let converted = WindowGeometry.appKitFrame(fromAX: original, primaryMaxY: primaryMaxY)
        pointer = CGPoint(x: converted.midX, y: converted.midY)
        drain(0.1)
        check(manager.state?.phase == .visible, "inactivity callback rechecks a cursor that returned")
        pointer = CGPoint(x: -100_000, y: -100_000)
        manager.updateSettings(settings)
        active = manager.state!.ownerPID
        drain(0.1)
        check(manager.state?.phase == .visible, "inactivity callback rechecks the active application")
        active = NSRunningApplication.current.processIdentifier
        manager.updateSettings(settings)
        settings.enableHideOnInactivity = false
        manager.updateSettings(settings)
        drain(0.32)
        check(manager.state?.phase == .visible && frames[CFHash(window)] == original,
              "disabled inactivity cancels a verified pending timer")
        manager.restoreAndClear()
    }

    do {
        let delay = CancellableDelay()
        var events: [Int] = []
        delay.schedule(after: 0.02) { events.append(1) }
        delay.cancel()
        drain(0.06)
        check(events.isEmpty, "cancelled delayed reveal never fires")
        delay.schedule(after: 0.02) { events.append(2) }
        delay.schedule(after: 0.02) { events.append(3) }
        drain(0.06)
        check(events == [3], "only the newest delayed reveal fires")
    }

    do {
        let converted = WindowGeometry.appKitFrame(fromAX: original, primaryMaxY: 900)
        check(converted == CGRect(x: 100, y: 500, width: 400, height: 300), "AX frame converts to AppKit once")
        let upperScreenAX = CGRect(x: -500, y: -700, width: 400, height: 300)
        check(WindowGeometry.appKitFrame(fromAX: upperScreenAX, primaryMaxY: 900).minY == 1300,
              "coordinate conversion supports negative origins and an upper display")
        var invalid = EdgeSettings()
        invalid.gripWidth = .infinity
        invalid.revealDelay = .nan
        invalid.selectedPID = Int.max
        let valid = invalid.validated()
        check(valid.gripWidth == 4 && valid.revealDelay == 0 && valid.selectedPID == nil,
              "non-finite settings and overflowing legacy PID are sanitized")
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.show()
        let resized = CGRect(x: 210, y: 180, width: 530, height: 320)
        frames[CFHash(window)] = resized
        manager.hide()
        manager.restoreAndClear()
        check(frames[CFHash(window)] == resized, "manual move and resize remain the restore destination")
    }

    do {
        let manager = makeManager()
        let (window, _) = makeWindow()
        manager.dock(axWindow: window, ownerPID: NSRunningApplication.current.processIdentifier,
                     side: .right, settings: EdgeSettings())
        rejectedWrites.insert(CFHash(window))
        manager.restoreAndClear()
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        check(manager.state == nil && manager.lastError == nil,
              "owner termination releases recovery state even after a failed restore")
        rejectedWrites.remove(CFHash(window))
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.show()
        manager.hide(animated: true)
        drain(0.05)
        // The edge must allow reveal before the hide animation has completed.
        if manager.state?.canReveal == true { manager.show(animated: true) }
        drain()
        check(manager.state?.phase == .visible && frames[CFHash(window)] == original,
              "edge reveal can reverse an in-flight hide without losing the destination")
        manager.restoreAndClear()
    }

    // Selection stores the pre-drag frame, never the frame at mouseUp near the edge.
    do {
        let manager = makeManager()
        let (window, pid) = makeWindow()
        frames[CFHash(window)] = original.offsetBy(dx: 600, dy: 20)
        let success = manager.dock(axWindow: window, ownerPID: pid, side: .right,
                                   settings: EdgeSettings(), restoreFrame: original)
        manager.show()
        check(success && frames[CFHash(window)] == original, "selection: reveal uses the pre-drag frame")
        manager.suspendInteraction(true)
        frames[CFHash(window)] = original.offsetBy(dx: 500, dy: 10)
        let again = manager.dock(axWindow: window, ownerPID: pid, side: .right,
                                 settings: EdgeSettings(), restoreFrame: original)
        manager.suspendInteraction(false)
        manager.restoreAndClear()
        check(again && frames[CFHash(window)] == original, "selection: re-dragging the same window preserves the safe frame")
    }

    do {
        let manager = makeManager()
        let first = dock(manager)
        let firstWrites = writes[CFHash(first)]
        let (second, pid) = makeWindow()
        let result = manager.dock(axWindow: second, ownerPID: pid, side: .right, settings: EdgeSettings(),
                                  restoreFrame: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100))
        check(!result && manager.state.map { CFEqual($0.axWindow, first) } == true
              && writes[CFHash(first)] == firstWrites && writes[CFHash(second)] == nil,
              "selection: invalid safe frame cannot replace or move either window")
        manager.restoreAndClear()
    }

    do {
        let manager = makeManager()
        _ = dock(manager)
        let oldSession = manager.state!.id
        let second = dock(manager)
        manager.clearClosedWindow(session: oldSession)
        check(manager.state.map { CFEqual($0.axWindow, second) } == true,
              "lifecycle: stale destruction cannot clear the new target")
        let before = writes[CFHash(second)]
        manager.clearClosedWindow(session: manager.state!.id)
        check(manager.state == nil && writes[CFHash(second)] == before,
              "lifecycle: confirmed destruction clears state without moving another window")
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.suspendInteraction(true)
        manager.show()
        check(manager.state?.isHidden == true, "gesture: suspension blocks accidental edge reveal")
        manager.suspendInteraction(false)
        manager.show()
        manager.suspendInteraction(true)
        var settings = EdgeSettings()
        settings.inactivityHideDelay = 0.01
        manager.updateSettings(settings)
        manager.hide()
        drain(0.08)
        check(manager.state?.phase == .visible, "gesture: suspension blocks hide even after settings refresh")
        check(manager.restoreAndClear() && frames[CFHash(window)] == original,
              "gesture: emergency restore remains available while interaction is suspended")
    }

    do {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let start = CGPoint(x: 200, y: 600)
        let moved = original.offsetBy(dx: 200, dy: 0)
        let pointer = CGPoint(x: 400, y: 600)
        func newIntent() -> WindowDragIntent { WindowDragIntent(initialFrame: original, initialPointer: start, screenFrame: screen) }
        var normal = newIntent()
        normal.update(frame: moved, pointer: pointer, modifier: false, insideTarget: true)
        check(!normal.release(modifier: false, insideTarget: true), "gesture: ordinary window drag never commits")
        var contents = newIntent()
        contents.update(frame: original, pointer: pointer, modifier: true, insideTarget: true)
        check(!contents.release(modifier: true, insideTarget: true), "gesture: moving content without moving the window never commits")
        var resized = newIntent()
        resized.update(frame: CGRect(x: 300, y: 100, width: 430, height: 300), pointer: pointer, modifier: true, insideTarget: true)
        check(resized.phase == .cancelled, "gesture: resizing cancels capture")
        var confirmed = newIntent()
        confirmed.update(frame: moved, pointer: pointer, modifier: true, insideTarget: true)
        check(confirmed.phase == .armed && confirmed.release(modifier: true, insideTarget: true),
              "gesture: moved window plus modifiers plus drop commits")
        confirmed.update(frame: moved, pointer: pointer, modifier: false, insideTarget: false)
        check(confirmed.phase == .committing, "gesture: releasing modifiers after mouseUp cannot cancel commit")
        var lostModifier = newIntent()
        lostModifier.update(frame: moved, pointer: pointer, modifier: true, insideTarget: true)
        lostModifier.update(frame: moved, pointer: pointer, modifier: false, insideTarget: true)
        check(!lostModifier.release(modifier: true, insideTarget: true), "gesture: modifier loss before mouseUp cancels the gesture permanently")
        var outside = newIntent()
        outside.update(frame: moved, pointer: pointer, modifier: true, insideTarget: true)
        check(!outside.release(modifier: true, insideTarget: false), "gesture: drop outside the target cancels")
        var escaped = newIntent()
        escaped.update(frame: moved, pointer: pointer, modifier: true, insideTarget: true)
        escaped.cancel()
        check(!escaped.release(modifier: true, insideTarget: true), "gesture: Escape prevents a later drop")
        var otherScreen = newIntent()
        otherScreen.update(frame: moved, pointer: CGPoint(x: 1200, y: 600), modifier: true, insideTarget: true)
        check(otherScreen.phase == .cancelled, "gesture: crossing to another screen cancels")
        var wrongMotion = newIntent()
        wrongMotion.update(frame: original.offsetBy(dx: -200, dy: 0), pointer: pointer, modifier: true, insideTarget: true)
        check(!wrongMotion.release(modifier: true, insideTarget: true), "gesture: unrelated window motion cannot arm capture")
        var vertical = newIntent()
        vertical.update(frame: original.offsetBy(dx: 0, dy: 100), pointer: CGPoint(x: 200, y: 500), modifier: true, insideTarget: true)
        check(vertical.release(modifier: true, insideTarget: true), "gesture: AX and AppKit vertical motion use opposite signs")
    }

    do {
        check(DragModifier.controlShift.matches([.control, .shift, .capsLock])
              && !DragModifier.controlShift.matches([.control, .shift, .option])
              && !DragModifier.controlShift.matches([.shift]), "gesture: modifier matching ignores caps lock but rejects extra keys")
        let saved = try JSONDecoder().decode(EdgeSettings.self, from: Data("{\"dragModifier\":\"futureValue\",\"gripWidth\":12}".utf8))
        check(saved.dragModifier == .controlShift && saved.gripWidth == 12,
              "settings: an unknown future modifier preserves other preferences")
        let left = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 0, y: 0, width: 1000, height: 800)
        check(!WindowGeometry.rightEdgeIsExternal(left, among: [left, right])
              && WindowGeometry.rightEdgeIsExternal(right, among: [left, right]), "displays: only an external right edge can accept a window")
        let distant = right.offsetBy(dx: 400, dy: 0)
        check(!WindowGeometry.rightEdgeIsExternal(left, among: [left, distant]), "displays: a gap does not make a right-hand display safe for off-screen hiding")
        let upper = right.offsetBy(dx: 0, dy: 900)
        check(WindowGeometry.rightEdgeIsExternal(left, among: [left, upper]), "displays: vertically separated screens do not block the right edge")
    }

    do {
        let (first, _) = makeWindow()
        let (second, _) = makeWindow()
        let extreme = SelectableWindow(id: UUID(), element: first, pid: 1_900_000_000,
            appName: "App", title: "", frame: CGRect(x: 0, y: 0, width: 1e100, height: 1e100),
            screenName: "Screen", unavailableReason: nil)
        check(extreme.detail.contains("App") && extreme.displayTitle == "Окно без заголовка",
              "catalog: extreme finite AX dimensions cannot overflow integer formatting")
        let owner = AXUIElementCreateApplication(1_900_000_000)
        windowLists[CFHash(owner)] = [first, second] as CFArray
        check(try WindowCatalog.contains(second, pid: 1_900_000_000),
              "catalog: matches the exact second AX element even with identical geometry")
        windowLists[CFHash(owner)] = [first] as CFArray
        check(try !WindowCatalog.contains(second, pid: 1_900_000_000),
              "catalog: cannot substitute another window when the selected one disappears")
        windowLists[CFHash(owner)] = ["not an AX element"] as CFArray
        var rejected = false
        do { _ = try WindowCatalog.windows(pid: 1_900_000_000) } catch { rejected = true }
        check(rejected, "catalog: malformed AXWindows entries are rejected before casting")
        windowLists[CFHash(owner)] = nil
        var failedRead = false
        do { _ = try WindowCatalog.contains(first, pid: 1_900_000_000) } catch { failedRead = true }
        check(failedRead, "catalog: an AX communication failure remains an error, not an empty list")
    }

    for error in [AXError.attributeUnsupported, .actionUnsupported] {
        let manager = makeManager()
        let window = dock(manager)
        raiseErrors[CFHash(window)] = error
        manager.show(animated: true)
        drain()
        check(manager.state?.phase == .visible && frames[CFHash(window)] == original && manager.lastError == nil,
              "reveal: unsupported raise (\(error.rawValue)) still returns the exact window")
        manager.restoreAndClear()
        raiseErrors[CFHash(window)] = nil
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        raiseErrors[CFHash(window)] = .attributeUnsupported
        rejectedWrites.insert(CFHash(window))
        manager.show()
        check(manager.state?.phase == .unavailable && manager.state?.lastVisibleFrame == original
              && manager.lastError?.contains("Перемещение окна") == true,
              "reveal: unsupported raise cannot mask a failed position write")
        rejectedWrites.remove(CFHash(window))
        raiseErrors[CFHash(window)] = nil
        manager.restoreAndClear()
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        unsupportedSizes.insert(CFHash(window))
        check(manager.restoreAndClear() && frames[CFHash(window)] == original,
              "restore: an unsupported size does not block position-only recovery of a hidden window")
        var correctContext = false
        do { _ = try AXWindowAccess().frame(of: window) }
        catch WindowAccessError.operationFailed(.readSize, let error) { correctContext = error == .attributeUnsupported }
        check(correctContext, "AX diagnostics: a size failure retains its operation and error code")
        unsupportedSizes.remove(CFHash(window))
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        unsupportedPositions.insert(CFHash(window))
        check(!manager.restoreAndClear() && manager.state?.lastVisibleFrame == original
              && manager.lastError?.contains("Чтение положения окна") == true,
              "restore: an unsupported position read cannot claim successful recovery")
        unsupportedPositions.remove(CFHash(window))
        check(manager.restoreAndClear(), "restore: position read failure remains recoverable on retry")
        let unsupported = WindowAccessError.accessibility(.attributeUnsupported).localizedDescription
        check(unsupported.contains("не поддерживает") && !unsupported.contains("Проверьте разрешение"),
              "AX diagnostics: unsupported properties are not described as missing permission")
    }

    do {
        let visible = CGRect(x: 0, y: 32, width: 1440, height: 846)
        let target = WindowGeometry.dropTargetFrame(in: visible)
        check(target == CGRect(x: 1188, y: 32, width: 252, height: 846),
              "drop region: Figma width, full screen height and no edge insets")
        check(target.contains(CGPoint(x: target.midX, y: target.minY + 1))
              && target.contains(CGPoint(x: target.midX, y: target.maxY - 1))
              && target.contains(CGPoint(x: target.midX, y: visible.minY + 1)),
              "drop region: accepts drops across the entire screen height")
        let translated = visible.offsetBy(dx: -1440, dy: -900)
        check(WindowGeometry.dropTargetFrame(in: translated) == target.offsetBy(dx: -1440, dy: -900),
              "drop region: supports displays with negative origins")
        check(WindowGeometry.dropTargetFrame(in: .zero).isEmpty,
              "drop region: unavailable visible area produces no target")
        let indicator = WindowGeometry.revealIndicatorFrame(in: visible, side: .right)
        check(indicator.size == CGSize(width: 30, height: 102.5) && indicator.midY == visible.midY
              && indicator.maxX == visible.maxX, "Figma indicator: centered on the display and flush with its right edge")
        check(WindowGeometry.revealIndicatorFrame(in: translated, side: .right) == indicator.offsetBy(dx: -1440, dy: -900),
              "Figma indicator: negative display origins preserve edge and center alignment")
        check(WindowGeometry.revealIndicatorFrame(in: .zero, side: .right).isEmpty,
              "Figma indicator: unavailable screen produces no panel")
    }

    do {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var intent = WindowDragIntent(initialFrame: original, initialPointer: CGPoint(x: 200, y: 600), screenFrame: screen)
        intent.update(frame: original.offsetBy(dx: 200, dy: 0), pointer: CGPoint(x: 400, y: 600), modifier: true, insideTarget: false)
        intent.update(frame: original.offsetBy(dx: 200, dy: 0), pointer: CGPoint(x: 520, y: 600), modifier: true, insideTarget: true)
        check(intent.phase == .armed, "drag stability: delayed AX coordinates do not dismiss a recognized drop region")
        intent.update(frame: original, pointer: CGPoint(x: 200, y: 600), modifier: true, insideTarget: false)
        check(intent.phase == .eligible, "drag stability: returning near the starting point does not flicker the region")
        intent.update(frame: original, pointer: CGPoint(x: 200, y: 600), modifier: false, insideTarget: false)
        check(intent.phase == .cancelled, "drag stability: latched recognition still cancels on modifier release")
        var resize = WindowDragIntent(initialFrame: original, initialPointer: CGPoint(x: 200, y: 600), screenFrame: screen)
        resize.update(frame: original.offsetBy(dx: 200, dy: 0), pointer: CGPoint(x: 400, y: 600), modifier: true, insideTarget: true)
        resize.update(frame: CGRect(x: 300, y: 100, width: 440, height: 300), pointer: CGPoint(x: 410, y: 600), modifier: true, insideTarget: true)
        check(resize.phase == .cancelled, "drag stability: resizing still cancels after recognition")
    }

    do {
        let animation = PanelEntranceAnimation()
        var values: [CGFloat] = []
        var completed = false
        animation.start(reduceMotion: false, update: { values.append($0) }, completion: { completed = true })
        animation.cancel()
        drain(0.22)
        check(values == [0] && !completed && !animation.isRunning,
              "panel entrance: cancellation prevents later frame writes and completion")
        var old: [CGFloat] = []
        animation.start(reduceMotion: false, update: { old.append($0) }, completion: { old.append(-1) })
        animation.start(reduceMotion: false, update: { values.append($0) }, completion: { completed = true })
        drain(0.25)
        check(old == [0] && completed && values.last == 1 && !animation.isRunning,
              "panel entrance: replacement completes only the newest animation")
        values.removeAll()
        animation.start(reduceMotion: true, update: { values.append($0) })
        check(values == [1] && !animation.isRunning, "panel entrance: Reduce Motion shows the destination immediately")
        check(PanelEntranceAnimation.easedProgress(-1) == 0 && PanelEntranceAnimation.easedProgress(1) == 1
              && PanelEntranceAnimation.easedProgress(0.09) > 0.5,
              "panel entrance: progress is bounded and eases out")
        let destination = CGRect(x: 1188, y: 0, width: 252, height: 900)
        check(PanelEntranceAnimation.frame(at: 0, destination: destination).minX == destination.maxX
              && PanelEntranceAnimation.frame(at: 1, destination: destination) == destination
              && PanelEntranceAnimation.frame(at: 0.5, destination: destination).minX > destination.minX,
              "panel entrance: slides left from beyond the right screen edge to its destination")
        values.removeAll()
        animation.start(reduceMotion: false, update: { values.append($0); animation.cancel() })
        drain(0.22)
        check(values == [0] && !animation.isRunning, "panel entrance: cancellation inside initial update cannot restart the timer")
    }

    do {
        let manager = makeManager()
        let window = dock(manager)
        let session = manager.state!.id
        var config = manager.state!.settings
        config.isEnabled = false
        check(manager.updateSettings(config) && manager.state?.phase == .paused
              && manager.state?.id == session && frames[CFHash(window)] == original,
              "pause: returns the window and retains the exact session")
        let moved = original.offsetBy(dx: 120, dy: 60)
        frames[CFHash(window)] = moved
        let before = writes[CFHash(window)]
        manager.hide(animated: true)
        manager.show(animated: true)
        manager.updateSettings(config)
        drain()
        check(frames[CFHash(window)] == moved && writes[CFHash(window)] == before,
              "pause: repeated pause and show/hide do not interfere with ordinary window movement")
        config.isEnabled = true
        check(manager.updateSettings(config) && manager.state?.isHidden == true
              && manager.state?.id == session && manager.state?.lastVisibleFrame == moved,
              "resume: hides the same window using its latest ordinary position")
        manager.restoreAndClear()
        check(frames[CFHash(window)] == moved, "resume: detach returns to the position captured on resume")
    }
    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.pause()
        let moved = original.offsetBy(dx: 80, dy: 80)
        frames[CFHash(window)] = moved
        let before = writes[CFHash(window)]
        check(manager.restoreAndClear() && manager.state == nil && frames[CFHash(window)] == moved
              && writes[CFHash(window)] == before,
              "detach: a paused ordinary window is released without another position write")
    }
    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.show(animated: true)
        drain(0.04)
        rejectedWrites.insert(CFHash(window))
        check(!manager.pause() && manager.state?.phase == .unavailable
              && manager.state?.settings.isEnabled == false && manager.state?.lastVisibleFrame == original,
              "pause failure: retains target and safe frame, disables automatic hiding")
        let before = writes[CFHash(window)]
        drain()
        check(writes[CFHash(window)] == before, "pause failure: cancelled reveal animation cannot continue writing")
        rejectedWrites.remove(CFHash(window))
        check(manager.pause() && manager.state?.phase == .paused && frames[CFHash(window)] == original,
              "pause failure: retry restores the same window")
        manager.restoreAndClear()
    }
    do {
        let manager = makeManager()
        let (window, pid) = makeWindow()
        check(manager.dock(axWindow: window, ownerPID: pid, side: .left, settings: EdgeSettings())
              && frames[CFHash(window)]!.minX == manager.state!.screenFrame.minX - original.width + 4,
              "left docking: hides beyond the left edge with the configured grip")
        let session = manager.state!.id
        manager.show(animated: true)
        drain(0.04)
        var config = manager.state!.settings
        config.side = .right
        check(manager.updateSettings(config) && manager.state?.side == .right && manager.state?.id == session,
              "side change: restores first and retains the exact window session")
        let destination = frames[CFHash(window)]
        drain()
        check(frames[CFHash(window)] == destination && manager.state?.lastVisibleFrame == original,
              "side change: old animation cannot move the window after switching")
        manager.restoreAndClear()
        check(frames[CFHash(window)] == original, "left/right round trip: restores the original safe frame")
    }
    do {
        let manager = makeManager()
        let window = dock(manager)
        var config = manager.state!.settings
        config.side = .left
        rejectedWrites.insert(CFHash(window))
        check(!manager.updateSettings(config) && manager.state?.side == .right
              && manager.state?.settings.side == .right && manager.state?.settings.isEnabled == false,
              "side change failure: preserves old side and recovery ownership")
        rejectedWrites.remove(CFHash(window))
        check(manager.updateSettings(config) && manager.state?.side == .left && manager.state?.isHidden == true,
              "side change failure: retry can restore and switch")
        manager.restoreAndClear()
    }
    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.pause()
        var config = manager.state!.settings
        config.side = .left
        let before = writes[CFHash(window)]
        check(manager.updateSettings(config) && manager.state?.side == .left
              && manager.state?.phase == .paused && writes[CFHash(window)] == before,
              "paused side change: changes preference without moving or hiding the window")
        config.isEnabled = true
        check(manager.updateSettings(config) && manager.state?.isHidden == true
              && frames[CFHash(window)]!.minX < manager.state!.screenFrame.minX,
              "paused side change: resume uses the newly selected left edge")
        manager.restoreAndClear()
    }
    do {
        let manager = makeManager()
        let window = dock(manager)
        manager.show()
        let session = manager.state!.id
        manager.suspendInteraction(true)
        frames[CFHash(window)] = original.offsetBy(dx: 1200, dy: 0)
        rejectedWrites.insert(CFHash(window))
        check(!manager.restoreAndClear(restoreFrame: original, session: session)
              && manager.state?.lastVisibleFrame == original && manager.state?.id == session,
              "detach gesture failure: pre-drag restore frame survives a failed drop return")
        rejectedWrites.remove(CFHash(window))
        check(manager.restoreAndClear() && frames[CFHash(window)] == original,
              "detach gesture failure: retry returns to pre-drag position, not the edge")
    }
    do {
        let manager = makeManager()
        let first = dock(manager)
        let stale = manager.state!.id
        let second = dock(manager)
        let before = writes[CFHash(second)]
        check(!manager.restoreAndClear(restoreFrame: original, session: stale)
              && manager.state.map { CFEqual($0.axWindow, second) } == true
              && writes[CFHash(second)] == before && frames[CFHash(first)] == original,
              "detach gesture: stale session cannot detach a replacement window")
        let bad = CGRect(x: CGFloat.nan, y: 0, width: 400, height: 300)
        check(!manager.restoreAndClear(restoreFrame: bad) && writes[CFHash(second)] == before,
              "detach gesture: invalid restore geometry is rejected before a write")
        manager.restoreAndClear()
    }
    do {
        let manager = makeManager()
        let (window, _) = makeWindow()
        manager.dock(axWindow: window, ownerPID: NSRunningApplication.current.processIdentifier,
                     side: .right, settings: EdgeSettings())
        manager.pause()
        manager.pause()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didTerminateApplicationNotification,
            object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        check(manager.state == nil, "pause lifecycle: repeated pause still observes owner termination")
    }
    do {
        let old = try JSONDecoder().decode(EdgeSettings.self, from: Data("{\"isEnabled\":false}".utf8))
        check(old.side == .right && !old.isEnabled, "settings migration: old preferences preserve disabled state and default to right")
        var config = EdgeSettings(); config.side = .left; config.isEnabled = false
        let decoded = try JSONDecoder().decode(EdgeSettings.self, from: JSONEncoder().encode(config))
        check(decoded == config, "settings: left side and pause preference survive serialization")
        let unknown = try JSONDecoder().decode(EdgeSettings.self, from: Data("{\"side\":\"future\"}".utf8))
        check(unknown.side == .right, "settings migration: unknown side safely falls back to right")
    }
    do {
        let left = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let right = CGRect(x: 0, y: -200, width: 1440, height: 900)
        check(WindowGeometry.edgeIsExternal(left, side: .left, among: [left, right])
              && !WindowGeometry.edgeIsExternal(right, side: .left, among: [left, right]),
              "left geometry: rejects an internal left boundary")
        let drop = WindowGeometry.dropTargetFrame(in: left, side: .left)
        let indicator = WindowGeometry.revealIndicatorFrame(in: left, side: .left)
        check(drop.minX == left.minX && drop.height == left.height && indicator.minX == left.minX
              && indicator.midY == left.midY, "left geometry: drop and indicator sit flush against the left screen edge")
        check(PanelEntranceAnimation.frame(at: 0, destination: drop, side: .left).maxX == left.minX
              && PanelEntranceAnimation.frame(at: 1, destination: drop, side: .left) == drop,
              "left entrance: slides right from beyond the left screen edge")
    }

    do {
        let manager = makeManager(screenFrames: {
            [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1440, y: 0, width: 1440, height: 900)]
        })
        let window = dock(manager)
        var config = manager.state!.settings; config.side = .left
        check(!manager.updateSettings(config) && manager.state?.phase == .paused
              && manager.state?.side == .right && frames[CFHash(window)] == original,
              "side change: blocked internal edge leaves the window safely paused on screen")
        manager.restoreAndClear()
    }

    do {
        var manager: FlankManager? = makeManager()
        let window = dock(manager!)
        manager!.pause()
        let moved = original.offsetBy(dx: 80, dy: 40)
        frames[CFHash(window)] = moved
        let before = writes[CFHash(window)]
        manager = nil
        check(frames[CFHash(window)] == moved && writes[CFHash(window)] == before,
              "pause lifecycle: deinit leaves an ordinary moved window untouched")
    }
    do {
        let manager = makeManager()
        let (window, pid) = makeWindow()
        var paused = EdgeSettings(); paused.isEnabled = false; paused.side = .left
        check(manager.dock(axWindow: window, ownerPID: pid, side: .left, settings: paused)
              && manager.state?.phase == .paused && frames[CFHash(window)] == original,
              "undo support: restoring a paused binding does not hide the previous window")
        manager.restoreAndClear()
    }

    print("\(checks - failures)/\(checks) passed; \(failures) failed")
    exit(failures == 0 ? 0 : 1)
}

try MainActor.assumeIsolated { try runTests() }
