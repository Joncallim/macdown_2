import Contributions
import DiagramsGraphviz
import Foundation
import GraphvizRendering
import Themes

/// Graphviz-specific supporting pieces for `ContributionRegistry.standardForExport`
/// (`MathExportRegistry.swift`, which owns the one real factory function).
/// Mirrors `MermaidExportRegistry.swift`'s exact shape.
extension ContributionRegistry {
    static let sharedGraphvizRenderer = GraphvizDiagramCache(renderer: GraphvizWebRenderer())

    /// `GraphvizWebRenderer.render`'s `context` parameter is not yet wired
    /// to Graphviz's own theming — same disclosed, deliberate scope limit
    /// already recorded for Mermaid (issue #79).
    static func graphvizRenderContext(theme: Theme, isPrintTarget _: Bool) -> GraphvizRenderContext {
        let foreground = theme.chrome.foreground
        let background = theme.chrome.background
        return GraphvizRenderContext(
            foregroundRed: foreground.red,
            foregroundGreen: foreground.green,
            foregroundBlue: foreground.blue,
            backgroundRed: background.red,
            backgroundGreen: background.green,
            backgroundBlue: background.blue
        )
    }
}
