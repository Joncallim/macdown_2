import SwiftUI

// MARK: - Snippets menu (EPIC-22 §6.18, Slice 9e)

extension WorkspaceCommands {
    var snippetCommands: some Commands {
        CommandMenu("Snippets") {
            Button("Insert Snippet…") {
                coordinator?.toggleInsertSnippet()
            }
            .keyboardShortcut("i", modifiers: [.control, .command])
            .disabled(coordinator?.keyModel?.hasActiveDocument != true)

            Button("Edit Snippets…") {
                coordinator?.editSnippets(relativeTo: NSApp.keyWindow)
            }
        }
    }
}
