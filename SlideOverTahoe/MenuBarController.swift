import Cocoa

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var leftToggleItem: NSMenuItem!
    private var rightToggleItem: NSMenuItem!

    override init() {
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.righthalf.inset.filled",
                accessibilityDescription: "SlideOver"
            )
        }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        leftToggleItem = NSMenuItem(title: "Левый край", action: #selector(toggleLeftEdge), keyEquivalent: "")
        leftToggleItem.target = self
        leftToggleItem.state = SettingsStore.shared.left.isEnabled ? .on : .off
        menu.addItem(leftToggleItem)

        rightToggleItem = NSMenuItem(title: "Правый край", action: #selector(toggleRightEdge), keyEquivalent: "")
        rightToggleItem.target = self
        rightToggleItem.state = SettingsStore.shared.right.isEnabled ? .on : .off
        menu.addItem(rightToggleItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Выход", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleLeftEdge() {
        SettingsStore.shared.left.isEnabled.toggle()
        leftToggleItem.state = SettingsStore.shared.left.isEnabled ? .on : .off
    }

    @objc private func toggleRightEdge() {
        SettingsStore.shared.right.isEnabled.toggle()
        rightToggleItem.state = SettingsStore.shared.right.isEnabled ? .on : .off
    }
}
