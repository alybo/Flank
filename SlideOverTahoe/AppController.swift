import Foundation
import Combine

final class AppController: ObservableObject {
    static let shared = AppController()

    let settings = SettingsStore.shared
    let rightEdge = EdgeController(side: .right)

    private var cancellables = Set<AnyCancellable>()

    private init() {
        settings.$right
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.rightEdge.apply(settings: v) }
            .store(in: &cancellables)

        // Apply initial
        rightEdge.apply(settings: settings.right)
    }
}
