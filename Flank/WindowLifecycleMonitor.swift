import ApplicationServices
import Cocoa

final class WindowLifecycleMonitor {
    private var observer: AXObserver?
    private var window: AXUIElement?
    private var pid: pid_t = 0
    private var poll: Timer?
    private var generation = UUID()
    var onClosed: (() -> Void)?
    var onRefresh: (() -> Void)?

    func watch(_ window: AXUIElement, pid: pid_t) {
        stop()
        self.window = window
        self.pid = pid
        var created: AXObserver?
        let result = AXObserverCreate(pid, { _, element, notification, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let monitor = Unmanaged<WindowLifecycleMonitor>.fromOpaque(context).takeUnretainedValue()
                guard let current = monitor.window, CFEqual(current, element) else { return }
                if notification as String == kAXUIElementDestroyedNotification { monitor.onClosed?() }
                else { monitor.onRefresh?() }
            }
        }, &created)
        if result == .success, let created {
            observer = created
            let context = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(created, window, name as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        // A bounded-rate fallback also covers applications with incomplete notifications.
        let token = generation
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.generation == token, let window = self.window else { return }
            // A window missing from AXWindows can be on another Space. Only an invalid
            // AX reference confirms destruction; timeouts retain the recovery state.
            do {
                _ = try WindowCatalog.attribute(window, kAXRoleAttribute)
                self.onRefresh?()
            } catch WindowAccessError.accessibility(let error) where error == .invalidUIElement {
                self.onClosed?()
            } catch { /* Retry on the next tick without discarding the window. */ }
        }
        poll = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        generation = UUID()
        poll?.invalidate()
        poll = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        window = nil
    }

    deinit { stop() }
}
