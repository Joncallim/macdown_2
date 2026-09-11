import AppKit
import SwiftUI
import TextFilters

/// The "Commands" menu: discovered user text filters, plus the two
/// deliberately manual affordances issue #15/epic-14-implementation.md §1
/// calls for instead of auto-installing anything — "Show Commands Folder"
/// and "Add Example Scripts". A separate `Commands` conformance from
/// `WorkspaceCommands`, composed alongside it in `MacDown2App`, so this
/// menu's discovery logic stays independently readable and neither file
/// grows toward SwiftLint's `type_body_length` budget.
struct TextFilterCommands: Commands {
    @Environment(\.windowCoordinator) private var coordinator

    var body: some Commands {
        CommandMenu("Commands") {
            Button("Command Palette…") {
                coordinator?.toggleCommandPalette()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            let commands = TextFilterCommandDiscovery.discoverCommands()
            if commands.isEmpty {
                Text("No Commands Installed")
            } else {
                ForEach(commands) { command in
                    Button(command.name) {
                        Task { await coordinator?.textFilterCoordinator.run(command) }
                    }
                    .accessibilityIdentifier("textFilterCommand.\(command.id)")
                }
                .disabled(coordinator?.textFilterCoordinator.canRunTextFilters != true)
            }

            Divider()

            Button("Show Commands Folder") {
                let directory = TextFilterCommandDiscovery.commandsDirectory
                // Discovery creates the directory as a side effect (§9); the
                // folder must exist before Finder can open it.
                _ = TextFilterCommandDiscovery.discoverCommands(in: directory)
                NSWorkspace.shared.open(directory)
            }

            Button("Add Example Scripts") {
                let installed = BundledExampleScripts.install(into: TextFilterCommandDiscovery.commandsDirectory)
                Self.presentAddExampleScriptsResult(installed)
            }
        }
    }

    /// `install(into:)` runs silently by design (it may run repeatedly as
    /// the user reopens this menu) but its *result* was never surfaced at
    /// all — a user clicking this had no way to tell whether it had done
    /// anything, short of separately opening "Show Commands Folder" to
    /// check (manual verification finding). A plain, undismissable-window
    /// `NSAlert` is deliberately not sheeted on any particular document
    /// window: unlike a text filter's failure, this action has no single
    /// originating window to sheet against.
    private static func presentAddExampleScriptsResult(_ installedCount: Int) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        if installedCount > 0 {
            alert.messageText = installedCount == 1
                ? "Added 1 Example Script"
                : "Added \(installedCount) Example Scripts"
            alert.informativeText = "They're now listed in the Commands menu."
        } else {
            alert.messageText = "Example Scripts Already Installed"
            alert.informativeText = "Nothing new to add — see \"Show Commands Folder\" for what's there."
        }
        alert.runModal()
    }
}
