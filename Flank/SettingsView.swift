import SwiftUI
import Cocoa

struct SettingsView: View {
    @StateObject private var store = SettingsStore.shared
    @ObservedObject private var manager = AppController.shared.edge.manager
    @ObservedObject private var edge = AppController.shared.edge
    @State private var pickerVisible = false

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(edge.selectedWindow?.displayTitle ?? "Окно не выбрано").font(.headline).lineLimit(1)
                    Text(edge.selectedWindow?.appName ?? "Выберите окно или перетащите его в область у края")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(edge.selectedWindow == nil ? "Выбрать окно…" : "Другое окно…") { pickerVisible = true }
                    .popover(isPresented: $pickerVisible) {
                        WindowPickerView(edge: edge) { pickerVisible = false }
                    }
            }
            if let message = edge.selectionMessage, manager.lastError == nil {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            if let error = manager.lastError {
                Text(error).font(.callout).foregroundStyle(.red)
                    .accessibilityLabel("Ошибка управления окном: \(error)")
            }
            Picker("Сторона закрепления", selection: $store.configuration.side) {
                ForEach(DockState.Side.allCases, id: \.self) { side in Text(side.label).tag(side) }
            }.pickerStyle(.segmented)
            if let state = manager.state {
                Toggle("Скрывать выбранное окно", isOn: Binding(
                    get: { state.settings.isEnabled },
                    set: { edge.setHidingEnabled($0) }
                ))
                Text(state.phase == .paused
                     ? "Скрытие на паузе. Окно остаётся выбранным — включите переключатель, чтобы снова спрятать его."
                     : "Выключение вернёт окно на экран и сохранит его выбор.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Отвязать окно") { edge.detach() }
                    if state.phase == .unavailable {
                        Button("Повторить возврат") { edge.setHidingEnabled(false) }
                    }
                }
            }
            if edge.canUndo { Button("Отменить последнее назначение") { edge.undoSelection() } }
            GroupBox("Закрепление и отвязка жестом") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Управлять привязкой перетаскиванием", isOn: $store.configuration.enableDragToDock)
                    Picker("Клавиши", selection: $store.configuration.dragModifier) {
                        ForEach(DragModifier.allCases) { modifier in Text(modifier.label).tag(modifier) }
                    }.disabled(!store.configuration.enableDragToDock)
                    Text("Начните двигать окно, затем зажмите выбранные клавиши и отпустите его в области у выбранного края. Для закреплённого окна появится «Отвязать окно» со стрелкой к центру экрана. Escape — отмена.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            EdgeColumnView(settings: $store.configuration)
            Text("Flank \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption).foregroundStyle(.secondary)
        }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: min(680, (NSScreen.main?.visibleFrame.height ?? 780) - 100))
    }
}

private struct EdgeColumnView: View {
    @Binding var settings: EdgeSettings


    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 14) {
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
                        Toggle("Показывать индикатор раскрытия", isOn: $settings.enableRevealIndicator)

                        HStack {
                            Text("Ширина области наведения (pt)")
                            Spacer()
                            Stepper(value: $settings.overlayWidth, in: 2...20, step: 1) {
                                Text("\(settings.overlayWidth, specifier: "%.0f")")
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }

                        HStack {
                            Text("Видимая кромка окна (pt)")
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

}
