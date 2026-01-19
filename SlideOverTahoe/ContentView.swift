import SwiftUI
import Cocoa

struct ContentView: View {
    @State private var axTrusted = Accessibility.isTrusted()

    var body: some View {
        Group {
            if axTrusted {
                SettingsView()
            } else {
                VStack(spacing: 12) {
                    Text("Нужен доступ Accessibility, чтобы двигать окна других приложений.")
                        .multilineTextAlignment(.center)

                    Text("Откройте System Settings → Privacy & Security → Accessibility и включите SlideOver.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Запросить доступ") {
                        Accessibility.requestTrust()
                    }

                    Button("Открыть настройки Accessibility") {
                        openAccessibilitySettings()
                    }

                    Button("Проверить снова") {
                        axTrusted = Accessibility.isTrusted()
                    }
                }
                .padding(16)
                .frame(width: 520)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            axTrusted = Accessibility.isTrusted()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
