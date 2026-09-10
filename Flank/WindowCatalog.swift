import ApplicationServices
import Cocoa

struct SelectableWindow: Identifiable {
    let id: UUID
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let title: String
    let frame: CGRect
    let screenName: String
    let unavailableReason: String?

    var displayTitle: String { title.isEmpty ? "Окно без заголовка" : title }
    var detail: String {
        // AX metadata is untrusted: finite CGFloat values can still overflow Int.
        let dimensions = String(format: "%.0f×%.0f", Double(frame.width), Double(frame.height))
        return "\(appName) · \(screenName) · \(dimensions)"
    }
}

enum WindowCatalog {
    static func list(side: DockState.Side = .right) async -> [SelectableWindow] {
        guard Accessibility.isTrusted() else { return [] }
        var result: [SelectableWindow] = []
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        for app in apps {
            guard !Task.isCancelled else { return [] }
            await Task.yield()
            guard let windows = try? windows(pid: app.processIdentifier) else { continue }
            for window in windows {
                guard !Task.isCancelled else { return [] }
                await Task.yield()
                if let item = try? describe(window, pid: app.processIdentifier, side: side) { result.append(item) }
            }
        }
        return result.sorted { ($0.appName, $0.displayTitle) < ($1.appName, $1.displayTitle) }
    }

    static func windows(pid: pid_t) throws -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let value = try attribute(app, kAXWindowsAttribute)
        guard let values = value as? [AnyObject], values.allSatisfy({ CFGetTypeID($0) == AXUIElementGetTypeID() }) else {
            throw WindowAccessError.invalidGeometry
        }
        return values.map { $0 as! AXUIElement } // Every element's CF type was checked above.
    }

    static func contains(_ element: AXUIElement, pid: pid_t) throws -> Bool {
        try windows(pid: pid).contains { CFEqual($0, element) }
    }

    static func describe(_ element: AXUIElement, pid: pid_t, id: UUID = UUID(), safeFrame: CGRect? = nil, side: DockState.Side = .right) throws -> SelectableWindow {
        AXUIElementSetMessagingTimeout(element, 0.2)
        let frame = try AXWindowAccess().frame(of: element)
        let role = try attribute(element, kAXRoleAttribute) as? String
        guard role == kAXWindowRole else { throw WindowAccessError.invalidGeometry }
        let app = NSRunningApplication(processIdentifier: pid)
        let title = (try? attribute(element, kAXTitleAttribute)) as? String ?? ""
        let subrole = (try? attribute(element, kAXSubroleAttribute)) as? String
        var movable = DarwinBoolean(false)
        let moveError = AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &movable)
        let geometryFrame = safeFrame ?? frame
        let screen = WindowGeometry.screen(forAX: geometryFrame)
        let reason: String?
        if pid == ProcessInfo.processInfo.processIdentifier { reason = "Служебное окно Flank" }
        else if subrole != kAXStandardWindowSubrole { reason = "Поддерживаются обычные окна приложения" }
        else if try bool(element, kAXMinimizedAttribute) { reason = "Сначала разверните окно" }
        else if try bool(element, "AXFullScreen") { reason = "Сначала выйдите из полноэкранного режима" }
        else if moveError != .success || !movable.boolValue { reason = "Приложение не разрешает перемещать это окно" }
        else if let screen {
            if !WindowGeometry.edgeIsExternal(screen.frame, side: side, among: NSScreen.screens.map(\.frame)) {
                reason = "На выбранной стороне находится другой экран — выберите внешний край"
            } else {
                let converted = WindowGeometry.appKitFrame(fromAX: geometryFrame, primaryMaxY: NSScreen.screens.first?.frame.maxY ?? 0)
                reason = screen.frame.insetBy(dx: -2, dy: -2).contains(converted) ? nil : "Сначала переместите окно целиком на экран"
            }
        } else { reason = "Экран окна недоступен" }
        return SelectableWindow(id: id, element: element, pid: pid, appName: app?.localizedName ?? "Приложение",
                                title: title, frame: frame, screenName: screen?.localizedName ?? "Нет экрана",
                                unavailableReason: reason)
    }

    static func candidate(at point: CGPoint, side: DockState.Side = .right) -> SelectableWindow? {
        guard let primary = NSScreen.screens.first else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(primary.frame.maxY - point.y), &hit) == .success,
              let hit else { return nil }
        let window: AXUIElement
        if (try? attribute(hit, kAXRoleAttribute)) as? String == kAXWindowRole {
            window = hit
        } else {
            guard let raw = try? attribute(hit, kAXWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            window = raw as! AXUIElement
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier,
              let candidate = try? describe(window, pid: pid, side: side), candidate.unavailableReason == nil else { return nil }
        return candidate
    }

    static func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success else { throw WindowAccessError.accessibility(error) }
        guard let value else { throw WindowAccessError.invalidGeometry }
        return value
    }

    private static func bool(_ element: AXUIElement, _ name: String) throws -> Bool {
        let value: CFTypeRef
        do { value = try attribute(element, name) }
        catch WindowAccessError.accessibility(let error) where error == .attributeUnsupported { return false }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { throw WindowAccessError.invalidGeometry }
        return CFBooleanGetValue((value as! CFBoolean))
    }
}
