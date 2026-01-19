import SwiftUI

@main
struct SlideOverTahoeApp: App {
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
    func applicationWillTerminate(_ notification: Notification) {
            SlideOverManagerRegistry.shared.restoreAll()
        }
}
