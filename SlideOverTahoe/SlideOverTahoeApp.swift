import SwiftUI

@main
struct SlideOverTahoeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Оставим обычное окно — удобно для дебага.
        // Позже можно убрать WindowGroup и оставить только менюбар.
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppController.shared
        menuBar = MenuBarController()
    }
    func applicationWillTerminate(_ notification: Notification) {
            SlideOverManagerRegistry.shared.restoreAll()
        }
}
