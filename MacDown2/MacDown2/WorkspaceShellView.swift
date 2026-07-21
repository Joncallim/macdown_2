import AppKit
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
        .focusedSceneValue(\.workspaceModel, model)
        .background(WindowTitleUpdater(model: model))
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

// MARK: - Window title / dirty dot

/// Keeps the owning `NSWindow` title and dirty-edited dot in sync with the
/// document shown in this view.
private struct WindowTitleUpdater: NSViewRepresentable {
    let model: WorkspaceModel

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let window = nsView.window else { return }
        let document = model.activeDocument

        let baseTitle = document?.fileURL?.lastPathComponent ?? "Untitled"
        let isDirty = document?.state == .dirty || document?.state == .conflict
        window.title = isDirty ? "● \(baseTitle)" : baseTitle
        window.representedURL = document?.fileURL
        window.isDocumentEdited = isDirty
    }
}
