import Cocoa
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        let root = ContentView()
        let hosting = NSHostingView(rootView: root)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "SlideOver"
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.center()

        super.init(window: w)
        w.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let w = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    // Красная кнопка: не закрываем навсегда, а просто прячем окно
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
