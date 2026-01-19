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
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
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

            Toggle("Включить \(title.lowercased())", isOn: $settings.isEnabled)
                .font(.headline)

            VStack(spacing: 14) {
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
                            Stepper(value: $settings.cursorLeaveHideDelay, in: 0...10, step: 0.5) {
                                Text("\(settings.cursorLeaveHideDelay, specifier: "%.1f")")
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                        .disabled(!settings.enableHideOnCursorLeave)

                        Divider()

                        Toggle("Скрывать при неактивности", isOn: $settings.enableHideOnInactivity)
                        HStack {
                            Text("Задержка при неактивности (сек)")
                            Spacer()
                            Stepper(value: $settings.inactivityHideDelay, in: 0...20, step: 0.5) {
                                Text("\(settings.inactivityHideDelay, specifier: "%.1f")")
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                        .disabled(!settings.enableHideOnInactivity)
                    }
                    .padding(.vertical, 6)
                }

                GroupBox("Выезд из края") {
                    HStack {
                        Text("Задержка выезда (сек)")
                        Spacer()
                        Stepper(value: $settings.revealDelay, in: 0...5, step: 0.1) {
                            Text("\(settings.revealDelay, specifier: "%.1f")")
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 6)
                }

                GroupBox("Зона срабатывания") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Ширина области наведения (px)")
                            Spacer()
                            Stepper(value: $settings.overlayWidth, in: 2...20, step: 1) {
                                Text("\(settings.overlayWidth, specifier: "%.0f")")
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }

                        HStack {
                            Text("Видимая кромка окна (px)")
                            Spacer()
                            Stepper(value: $settings.gripWidth, in: 1...16, step: 1) {
                                Text("\(settings.gripWidth, specifier: "%.0f")")
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .disabled(!settings.isEnabled)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func refreshApps() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

}
