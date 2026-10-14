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

    static func graphvizRenderContext(theme: Theme, isPrintTarget _: Bool) -> GraphvizRenderContext {
        .neutralLight
    }
}
