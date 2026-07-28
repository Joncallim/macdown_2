import EditorCore
import Highlighting
import MarkdownEngine
import Preview
import SwiftUI
import Themes
import Workspace

// MARK: - Previews

#Preview("Split editor & preview") {
    @MainActor in
    contentAreaPreview(
        layout: .split(fraction: 0.5),
        text: "# Split Preview\n\nHello, world."
    )
}

#Preview("Editor only") {
    @MainActor in
    contentAreaPreview(
        layout: .editorOnly,
        text: "# Editor Only\n\nJust the source pane."
    )
}

#Preview("Preview only") {
    @MainActor in
    contentAreaPreview(
        layout: .previewOnly,
        text: "# Preview Only\n\nJust the rendered pane."
    )
}

@MainActor
private func contentAreaPreview(
    layout: PreviewLayoutMode,
    text: String
) -> some View {
    let model = WorkspaceModel(tabStore: TabStore())
    model.newDocument()
    model.tabStore.updateActiveDocument {
        $0.edited(text: text)
    }
    if let activeTabID = model.tabStore.activeTabID {
        model.tabStore.setPreviewLayout(layout, for: activeTabID)
    }

    return ContentAreaView(
        model: model,
        editorStore: EditorTextSystemStore(),
        highlightStore: SyntaxHighlightStore(),
        parseStore: MarkdownParseStore(),
        themeController: ThemeController()
    )
}
