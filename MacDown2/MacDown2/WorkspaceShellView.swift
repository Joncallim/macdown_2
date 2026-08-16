import EditorCore
import FileTree
import Highlighting
import JSONSupport
import MarkdownEngine
import OutlineUI
import SwiftUI
import Themes
import Workspace

/// The content of a single MacDown 2 document window.
///
/// With native window tabbing, each tab/window hosts its own `WorkspaceModel`
/// showing one document. The tab bar itself is provided by AppKit; this view
/// only renders the sidebar and content area for the document assigned to the
/// window.
struct WorkspaceShellView: View {
    @State private var model: WorkspaceModel
    let editorStore: EditorTextSystemStore
    let highlightStore: SyntaxHighlightStore
    let parseStore: MarkdownParseStore
    let jsonAnalysisStore: JSONAnalysisStore
    let themeController: ThemeController
    let outlineController: OutlineController
    let fileTreeModel: FileTreeModel
    let externalFileController: ExternalFileController

    init(
        model: WorkspaceModel,
        editorStore: EditorTextSystemStore,
        highlightStore: SyntaxHighlightStore,
        parseStore: MarkdownParseStore,
        jsonAnalysisStore: JSONAnalysisStore,
        themeController: ThemeController,
        outlineController: OutlineController,
        fileTreeModel: FileTreeModel,
        externalFileController: ExternalFileController
    ) {
        _model = State(initialValue: model)
        self.editorStore = editorStore
        self.highlightStore = highlightStore
        self.parseStore = parseStore
        self.jsonAnalysisStore = jsonAnalysisStore
        self.themeController = themeController
        self.outlineController = outlineController
        self.fileTreeModel = fileTreeModel
        self.externalFileController = externalFileController
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
            SidebarView(model: model, outlineController: outlineController, fileTreeModel: fileTreeModel)
        } detail: {
            ContentAreaView(
                model: model,
                editorStore: editorStore,
                highlightStore: highlightStore,
                parseStore: parseStore,
                jsonAnalysisStore: jsonAnalysisStore,
                themeController: themeController,
                outlineController: outlineController,
                externalFileController: externalFileController
            )
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.previewLayout, model.tabStore.activeTab?.previewLayout ?? .defaultMode)
        .task(id: themeController.current) {
            highlightStore.applyThemeToAll(themeController.current)
        }
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
