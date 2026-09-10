import Foundation

final class FlankManagerRegistry {
    static let shared = FlankManagerRegistry()

    private let table = NSHashTable<AnyObject>.weakObjects()
    private let lock = NSLock()

    private init() {}

    func register(_ manager: FlankManager) {
        lock.lock(); defer { lock.unlock() }
        table.add(manager)
    }

    @discardableResult
    func restoreAll() -> Bool {
        lock.lock()
        let managers = table.allObjects.compactMap { $0 as? FlankManager }
        lock.unlock()
        var restored = true
        for manager in managers {
            if !manager.restoreAndClear() { restored = false }
        }
        return restored
    }
}
