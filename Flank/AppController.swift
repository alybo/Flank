import Foundation
import Combine

final class AppController: ObservableObject {
    static let shared = AppController()

    let settings = SettingsStore.shared
    let edge = EdgeController()
    private var dragCapture: WindowDragCaptureController?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        dragCapture = WindowDragCaptureController(edge: edge)
        settings.$configuration
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.dragCapture?.apply(settings: v)
                self?.edge.apply(settings: v)
            }
            .store(in: &cancellables)

    }
}
