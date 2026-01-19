import SwiftUI
import Cocoa

struct SettingsView: View {
    @StateObject private var store = SettingsStore.shared

    var body: some View {
        HStack(spacing: 16) {
            EdgeColumnView(title: "Левый край", settings: $store.left)
            Divider()
            EdgeColumnView(title: "Правый край", settings: $store.right)
        }
        .padding(14)
        .frame(width: 760, height: 420)
    }
}

private struct EdgeColumnView: View {
    let title: String
    @Binding var settings: EdgeSettings

    @State private var apps: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)

            HStack(spacing: 8) {
                Picker("Программа", selection: Binding<String?>(
                    get: { settings.selectedBundleID },
                    set: { settings.selectedBundleID = $0 }
                )) {
                    Text("Ничего").tag(String?.none)
                    ForEach(apps, id: \.bundleIdentifier) { app in
                        Text(app.localizedName ?? "App").tag(app.bundleIdentifier)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    refreshApps()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Обновить список приложений")
            }
            .onChange(of: settings.selectedBundleID) { _ in
                settings.selectedPID = nil
            }
            .onAppear {
                refreshApps()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
                refreshApps()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
                refreshApps()
            }

            GroupBox("Режимы скрытия") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Скрывать, когда курсор ушёл", isOn: $settings.enableHideOnCursorLeave)
                    HStack {
                        Text("Задержка скрытия (сек)")
                        Spacer()
                        TextField("", value: $settings.cursorLeaveHideDelay, formatter: numberFormatter)
                            .frame(width: 70)
                    }

                    Divider()

                    Toggle("Скрывать при неактивности", isOn: $settings.enableHideOnInactivity)
                    HStack {
                        Text("Задержка при неактивности (сек)")
                        Spacer()
                        TextField("", value: $settings.inactivityHideDelay, formatter: numberFormatter)
                            .frame(width: 70)
                    }
                }
                .padding(.vertical, 6)
            }

            GroupBox("Выезд из края") {
                HStack {
                    Text("Задержка выезда (сек)")
                    Spacer()
                    TextField("", value: $settings.revealDelay, formatter: numberFormatter)
                        .frame(width: 70)
                }
                .padding(.vertical, 6)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func refreshApps() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private var numberFormatter: NumberFormatter {
        let nf = NumberFormatter()
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 1
        nf.decimalSeparator = "."
        return nf
    }
}
