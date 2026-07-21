import SwiftUI
import Workspace

/// The content of a single MacDown 2 document window.
///
/// With native window tabbing, each tab/window hosts its own `WorkspaceModel`
/// showing one document. The tab bar itself is provided by AppKit; this view
/// only renders the sidebar and content area for the document assigned to the
/// window.
struct WorkspaceShellView: View {
    @State private var model: WorkspaceModel

    init(model: WorkspaceModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
            SidebarView(model: model)
        } detail: {
            ContentAreaView(document: model.activeDocument)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.sidebarVisible.toggle()
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
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
