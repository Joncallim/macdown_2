import Contributions
import DiagramRendering
import Diagrams
import Foundation
import Themes

/// Mermaid-specific supporting pieces for `ContributionRegistry.standardForExport`
/// (`MathExportRegistry.swift`, which owns the one real factory function —
/// see that file for why `MermaidContribution` is registered for Export
/// only, never for Preview: epic-20-implementation.md §2.2 invariant,
/// identical reasoning to Math's own).
extension ContributionRegistry {
    /// One process-lifetime, shared renderer/cache instance backs both
    /// Export (`standardForExport`) and Preview (`MermaidPreviewRenderer`,
    /// Slice 4) — a diagram already rendered for one is not re-rendered for
    /// the other, per the cache's own content-addressed keying
    /// (`MermaidDiagramCache`, epic-20-implementation.md §5).
    static let sharedMermaidRenderer = MermaidDiagramCache(renderer: MermaidWebRenderer())

    /// Mermaid uses the approved neutral-light-v1 palette for every
    /// destination. The returned SVG is authored with opaque neutral canvas
    /// and default text colors, so a dark editor theme cannot produce
    /// light-on-white export artwork or a mismatched preview canvas.
    static func mermaidRenderContext(theme _: Theme, isPrintTarget _: Bool) -> MermaidRenderContext {
        .neutralLight
    }
}
