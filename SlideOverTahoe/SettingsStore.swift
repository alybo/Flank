import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var left = EdgeSettings()
    @Published var right = EdgeSettings()

    private let keyLeft = "edge_settings_left"
    private let keyRight = "edge_settings_right"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        left = load(key: keyLeft) ?? EdgeSettings()
        right = load(key: keyRight) ?? EdgeSettings()

        $left
            .dropFirst()
            .sink { [weak self] v in self?.save(v, key: self?.keyLeft ?? "") }
            .store(in: &cancellables)

        $right
            .dropFirst()
            .sink { [weak self] v in self?.save(v, key: self?.keyRight ?? "") }
            .store(in: &cancellables)
    }

    private func load(key: String) -> EdgeSettings? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EdgeSettings.self, from: data)
    }

    private func save(_ value: EdgeSettings, key: String) {
        guard !key.isEmpty else { return }
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
