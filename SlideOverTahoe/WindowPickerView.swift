import SwiftUI
import Cocoa
import Combine

struct WindowPickerView: View {
    @State private var windows: [WindowInfo] = []
    @State private var selectedID: WindowInfo.ID?

    private var selected: WindowInfo? {
        guard let id = selectedID else { return nil }
        return windows.first(where: { $0.id == id })
    }

    @StateObject private var manager = SlideOverManager()
    private let overlay = EdgeOverlayController()

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Обновить список") { windows = WindowLister.listWindows() }
                Spacer()
            }

            List(windows, selection: $selectedID) { w in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(w.ownerName) — \(w.title.isEmpty ? "Untitled" : w.title)")
                        .lineLimit(1)
                    Text("pid \(w.ownerPID) • id \(w.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(w.id)
            }
            .frame(height: 260)

            HStack {
                Button("Dock Left") { dock(.left) }.disabled(selected == nil)
                Button("Dock Right") { dock(.right) }.disabled(selected == nil)
                Button("Show") { manager.show(animated: false) }.disabled(manager.state == nil)
                Button("Hide") { manager.hide(animated: false) }.disabled(manager.state == nil)
            }
        }
        .padding()
        .onAppear {
            windows = WindowLister.listWindows()
        }
    }

    private func dock(_ side: DockState.Side) {
        guard let sel = selected else { return }
        guard let ax = AXWindowResolver.resolveAXWindow(pid: sel.ownerPID, cgBounds: sel.bounds) else { return }

        manager.dock(axWindow: ax, ownerPID: sel.ownerPID, side: side, grip: 4, settings: EdgeSettings())

        // Edge overlay на экране, где окно
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: sel.bounds.midX, y: sel.bounds.midY)) } ?? NSScreen.main!
        overlay.onEnter = { [weak manager] in
            manager?.show(animated: false)
        }
        overlay.showOnScreen(side: side, screen: screen, width: 6)
    }
}
