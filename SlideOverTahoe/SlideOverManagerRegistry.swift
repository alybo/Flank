import Foundation

final class SlideOverManagerRegistry {
    static let shared = SlideOverManagerRegistry()

    private let table = NSHashTable<AnyObject>.weakObjects()
    private let lock = NSLock()

    private init() {}

    func register(_ manager: SlideOverManager) {
        lock.lock(); defer { lock.unlock() }
        table.add(manager)
    }

    func restoreAll() {
        lock.lock(); defer { lock.unlock() }
        for obj in table.allObjects {
            (obj as? SlideOverManager)?.restoreAndClear()
        }
    }
}
