import SwiftUI

@main
struct MacDown2App: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceShellView()
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            WorkspaceCommands()
        }
    }
}
