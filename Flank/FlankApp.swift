import SwiftUI

@main
struct FlankApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppController.shared
        menuBar = MenuBarController()
        SettingsWindowController.shared.show()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !FlankManagerRegistry.shared.restoreAll() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Не удалось вернуть окно"
        alert.informativeText = "Окно может остаться за экраном. Можно остаться в Flank и повторить возврат через меню или настройки."
        alert.addButton(withTitle: "Остаться")
        alert.addButton(withTitle: "Выйти без возврата")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
