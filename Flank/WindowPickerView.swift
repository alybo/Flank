import SwiftUI
import Cocoa

struct WindowPickerView: View {
    @ObservedObject var edge: EdgeController
    var onClose: () -> Void
    @State private var windows: [SelectableWindow] = []
    @State private var selectedID: UUID?
    @State private var loading = false
    @State private var refreshID = UUID()

    private var selected: SelectableWindow? { windows.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Какое окно убрать?").font(.headline)
                Spacer()
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                    .help("Обновить список окон").disabled(loading)
            }
            if !Accessibility.isTrusted() {
                Text("Разрешите доступ Accessibility в системных настройках, затем обновите список.")
                    .foregroundStyle(.secondary)
            } else if windows.isEmpty && !loading {
                Text("Открытых подходящих окон не найдено. Откройте окно приложения и обновите список.")
                    .foregroundStyle(.secondary)
            }
            if loading { ProgressView("Получение окон…") }
            List(windows, selection: $selectedID) { window in
                HStack(spacing: 10) {
                    if let icon = NSRunningApplication(processIdentifier: window.pid)?.icon {
                        Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(window.displayTitle).lineLimit(1)
                        Text(window.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let reason = window.unavailableReason {
                            Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .tag(window.id)
                .onTapGesture { choose(window) }
                .accessibilityElement(children: .combine)
                .accessibilityAction { choose(window) }
            }
            .frame(height: 300)
            if let message = edge.selectionMessage {
                Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Закрыть", action: onClose).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Убрать окно") { if let selected { choose(selected) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || selected?.unavailableReason != nil)
            }
        }
        .padding(16).frame(width: 460)
        .task(id: refreshID) {
            loading = true
            let result = await WindowCatalog.list(side: edge.side)
            guard !Task.isCancelled else { return }
            windows = result
            selectedID = nil
            loading = false
        }
    }

    private func choose(_ window: SelectableWindow) {
        selectedID = window.id
        guard window.unavailableReason == nil else { return }
        if edge.select(window) { onClose() }
    }

    private func refresh() {
        guard !loading else { return }
        loading = true
        refreshID = UUID()
    }
}
