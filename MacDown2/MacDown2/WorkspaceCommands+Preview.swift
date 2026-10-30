import SwiftUI

extension WorkspaceCommands {
    var previewMenu: some View {
        Menu("Preview") {
            Button("Choose Preview Resources Folder…") {
                coordinator?.chooseKeyPreviewResources()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(coordinator?.canChooseKeyPreviewResources != true)

            Button("Show HTML Source") {
                coordinator?.setKeyHTMLPreviewMode(.source)
            }
            .keyboardShortcut("4", modifiers: [.command, .option])
            .disabled(coordinator?.canSetKeyHTMLPreviewMode != true)

            Button("Show Rendered HTML") {
                coordinator?.setKeyHTMLPreviewMode(.rendered)
            }
            .keyboardShortcut("5", modifiers: [.command, .option])
            .disabled(coordinator?.canSetKeyHTMLPreviewMode != true)
        }
    }
}
