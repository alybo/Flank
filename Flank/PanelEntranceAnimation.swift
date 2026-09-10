import Cocoa

// Animates only our UI panels, never the application's selected AX window.
final class PanelEntranceAnimation {
    static let duration: TimeInterval = 0.18
    private var timer: Timer?
    var isRunning: Bool { timer != nil }

    static func easedProgress(_ elapsed: TimeInterval) -> CGFloat {
        let t = min(1, max(0, elapsed / duration))
        return CGFloat(1 - pow(1 - t, 3))
    }

    static func frame(at progress: CGFloat, destination: CGRect, side: DockState.Side = .right) -> CGRect {
        destination.offsetBy(dx: (side == .right ? 1 : -1) * destination.width * (1 - min(1, max(0, progress))), dy: 0)
    }

    func start(reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
               update: @escaping (CGFloat) -> Void, completion: (() -> Void)? = nil) {
        cancel()
        if reduceMotion { update(1); completion?(); return }
        let began = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self, self.timer === timer else { timer.invalidate(); return }
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            if elapsed >= Self.duration {
                self.cancel()
                update(1)
                completion?()
            } else { update(Self.easedProgress(elapsed)) }
        }
        self.timer = timer
        update(0)
        if self.timer === timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func cancel() { timer?.invalidate(); timer = nil }
    deinit { cancel() }
}
