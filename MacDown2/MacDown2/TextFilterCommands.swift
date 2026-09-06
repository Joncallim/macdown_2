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
                BundledExampleScripts.install(into: TextFilterCommandDiscovery.commandsDirectory)
            }
        }
    }
}
