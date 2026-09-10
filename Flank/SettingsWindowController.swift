import Cocoa
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        let root = ContentView()
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let initialSize = hosting.fittingSize
        let fallbackSize = NSSize(width: 520, height: 320)
        let size = initialSize == .zero ? fallbackSize : initialSize

        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered,
                         defer: false)
        w.title = "Flank"
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.center()
        w.setContentSize(size)

        super.init(window: w)
        w.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let w = window else { return }
        if let hosting = w.contentView as? NSHostingView<ContentView> {
            hosting.layoutSubtreeIfNeeded()
            let fitting = hosting.fittingSize
            if fitting != .zero {
                w.setContentSize(fitting)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    // Красная кнопка: не закрываем навсегда, а просто прячем окно
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
