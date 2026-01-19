import SwiftUI

struct ContentView: View {
    @State private var axTrusted = Accessibility.isTrusted()

    var body: some View {
        Group {
            if axTrusted {
                SettingsView()
            } else {
                VStack(spacing: 12) {
                    Text("Нужен доступ Accessibility, чтобы двигать окна других приложений.")

                    Button("Запросить доступ") {
                        Accessibility.requestTrust()
                    }

                    Button("Проверить снова") {
                        axTrusted = Accessibility.isTrusted()
                    }
                }
                .padding(16)
                .frame(width: 520, height: 220)
            }
        }
        .onAppear {
            axTrusted = Accessibility.isTrusted()
        }
    }
}
