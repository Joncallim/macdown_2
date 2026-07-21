import SwiftUI

@main
struct MacDown2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .commands {
            WorkspaceCommands()
        }
        .environment(\.windowCoordinator, appDelegate.coordinator)
    }
}
