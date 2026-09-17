import Contributions
import Diagrams
import SwiftUI

/// Split out from `DocumentEditorSplitView` purely to stay under
/// SwiftLint's `type_body_length` limit — matching this file's own existing
/// `DocumentEditorSplitView+Divider.swift` precedent for splitting a large
/// view's supporting code into a same-type extension file rather than
/// shrinking the view itself.
extension DocumentEditorSplitView {
    /// Threaded into `TextualMarkdownPreview.mermaidFenceView`
    /// (epic-20-implementation.md §7.2, §16) so a ```mermaid``` fence
    /// renders as a native diagram instead of Textual's ordinary code-block
    /// text. Uses the same shared renderer instance Export also uses
    /// (`ContributionRegistry.sharedMermaidRenderer`, via
    /// `MermaidPreviewRenderer.shared`) so a diagram already rendered for
    /// one destination is not re-rendered for the other.
    func mermaidFenceView(_ source: String) -> AnyView {
        AnyView(
            MermaidDiagramBlockView(
                source: source,
                context: ContributionRegistry.mermaidRenderContext(
                    theme: themeController.current, isPrintTarget: false
                ),
                renderer: MermaidPreviewRenderer.shared
            )
        )
    }
}
