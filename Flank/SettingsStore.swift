import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var configuration = EdgeSettings()

    private let keyRight = "edge_settings_right"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let saved = load(key: keyRight) {
            configuration = saved
        } else if let data = UserDefaults.standard.persistentDomain(forName: "Turbo.SlideOverTahoe")?[keyRight] as? Data,
                  let previous = try? JSONDecoder().decode(EdgeSettings.self, from: data) {
            configuration = previous
            save(previous, key: keyRight)
        } else { configuration = EdgeSettings() }

        $configuration
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
        if let data = try? JSONEncoder().encode(value.validated()) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
