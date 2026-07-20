import AppKit
import SwiftUI
import Workspace

struct WorkspaceShellView: View {
    @State private var model = WorkspaceModel(panel: NSFilePanelProvider())

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
            SidebarView(model: model)
        } detail: {
            ContentAreaView(document: model.activeDocument)
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.workspaceModel, model)
        .alert("Unsaved Changes", isPresented: $model.pendingClose) {
            Button("Save", role: .none) {
                Task { await model.resolveClose(.save) }
            }
            Button("Discard Changes", role: .destructive) {
                Task { await model.resolveClose(.discard) }
            }
            Button("Cancel", role: .cancel) {
                Task { await model.resolveClose(.cancel) }
            }
        } message: {
            Text("Do you want to save changes to this document?")
        }
    }

    private var sidebarVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { model.sidebarVisible ? .all : .detailOnly },
            set: { newValue in
                model.sidebarVisible = newValue != .detailOnly
            }
        )
    }
}
