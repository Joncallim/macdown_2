import Contributions
import DiagramsD2
import DiagramsGraphviz
import SwiftUI

/// Split out from `DocumentEditorSplitView` purely to stay under
/// SwiftLint's `type_body_length` limit, mirroring
/// `DocumentEditorSplitView+Mermaid.swift`'s exact precedent.
extension DocumentEditorSplitView {
    /// Threaded into `TextualMarkdownPreview.d2FenceView`
    /// (epic-21-implementation.md §3.5, §5 Slice 4) so a ```d2``` fence
    /// renders as a native diagram instead of Textual's ordinary code-block
    /// text. Uses the same shared renderer instance Export also uses
    /// (`ContributionRegistry.sharedD2Renderer`, via `D2PreviewRenderer.shared`)
    /// so a diagram already rendered for one destination is not re-rendered
    /// for the other.
    func d2FenceView(_ source: String) -> AnyView {
        AnyView(
            D2DiagramBlockView(
                source: source,
                context: ContributionRegistry.d2RenderContext(
                    theme: themeController.current, isPrintTarget: false
                ),
                renderer: D2PreviewRenderer.shared
            )
        )
    }

    /// Threaded into `TextualMarkdownPreview.graphvizFenceView`, mirroring
    /// `d2FenceView(_:)` above.
    func graphvizFenceView(_ source: String) -> AnyView {
        AnyView(
            GraphvizDiagramBlockView(
                source: source,
                context: ContributionRegistry.graphvizRenderContext(
                    theme: themeController.current, isPrintTarget: false
                ),
                renderer: GraphvizPreviewRenderer.shared
            )
        )
    }
}
