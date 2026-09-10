import Cocoa
import SwiftUI

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var hidingToggleItem: NSMenuItem!
    private var restoreItem: NSMenuItem!
    private var errorItem: NSMenuItem!
    private let picker = NSPopover()

    override init() {
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.righthalf.inset.filled",
                accessibilityDescription: "Flank"
            )
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        let chooseItem = NSMenuItem(title: "Выбрать окно…", action: #selector(chooseWindow), keyEquivalent: "")
        chooseItem.target = self
        menu.addItem(chooseItem)

        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        hidingToggleItem = NSMenuItem(title: "Скрывать выбранное окно", action: #selector(toggleHiding), keyEquivalent: "")
        hidingToggleItem.target = self
        hidingToggleItem.state = SettingsStore.shared.configuration.isEnabled ? .on : .off
        menu.addItem(hidingToggleItem)

        restoreItem = NSMenuItem(title: "Отвязать окно", action: #selector(detachWindow), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)
        errorItem = NSMenuItem(title: "Не удалось переместить окно — проверьте настройки", action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        menu.addItem(errorItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Выход", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleHiding() {
        let edge = AppController.shared.edge
        edge.setHidingEnabled(!(edge.manager.state?.settings.isEnabled ?? false))
        if edge.manager.lastError != nil || edge.selectionMessage != nil {
            SettingsWindowController.shared.show()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let manager = AppController.shared.edge.manager
        hidingToggleItem.state = manager.state?.settings.isEnabled == true ? .on : .off
        hidingToggleItem.isEnabled = manager.state != nil
        restoreItem.isEnabled = manager.state != nil
        errorItem.isHidden = manager.lastError == nil && AppController.shared.edge.selectionMessage == nil
    }

    @objc private func detachWindow() {
        AppController.shared.edge.detach()
        if AppController.shared.edge.manager.lastError != nil {
            SettingsWindowController.shared.show()
        }
    }

    @objc private func chooseWindow() {
        guard let button = statusItem.button else { return }
        picker.behavior = .transient
        picker.contentViewController = NSHostingController(rootView: WindowPickerView(edge: AppController.shared.edge) { [weak self] in
            self?.picker.performClose(nil)
        })
        NSApp.activate()
        picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
