import SwiftUI
import Themes

@main
struct MacDown2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .commands {
            WorkspaceCommands(themeController: appDelegate.themeController)
        }
        .environment(\.windowCoordinator, appDelegate.coordinator)
        .environment(\.themeController, appDelegate.themeController)
    }
}
