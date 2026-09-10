import Foundation

// Generation checks also protect work already enqueued when cancellation occurs.
final class CancellableDelay {
    private var work: DispatchWorkItem?
    private var generation = UUID()

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancel()
        let token = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.work = nil
            action()
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
    }

    func cancel() {
        generation = UUID()
        work?.cancel()
        work = nil
    }

    deinit { work?.cancel() }
}
