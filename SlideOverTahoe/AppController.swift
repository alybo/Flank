import Foundation
import Combine

final class AppController: ObservableObject {
    static let shared = AppController()

    let settings = SettingsStore.shared
    let leftEdge = EdgeController(side: .left)
    let rightEdge = EdgeController(side: .right)

    private var cancellables = Set<AnyCancellable>()

    private init() {
        settings.$left
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.leftEdge.apply(settings: v) }
            .store(in: &cancellables)

        settings.$right
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.rightEdge.apply(settings: v) }
            .store(in: &cancellables)

        // Apply initial
        leftEdge.apply(settings: settings.left)
        rightEdge.apply(settings: settings.right)
    }
}
