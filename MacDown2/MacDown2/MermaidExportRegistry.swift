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

    /// `MermaidWebRenderer.render`'s `context` parameter is not yet wired to
    /// Mermaid's own theming (epic-20-implementation.md §6, a documented
    /// Slice 2 limitation) — every diagram currently renders with Mermaid's
    /// default theme regardless of `isPrintTarget` or the live app theme.
    /// This function still threads real theme colors through today so that
    /// wiring Mermaid's own theme variables later (§18 residual work) is an
    /// addition to `MermaidWebRenderer`'s JavaScript call, not a second
    /// plumbing pass through every caller. `MathExportRegistry`'s own
    /// print-safety lesson — a raster equation's baked-in colors cannot be
    /// recolored by `structural.css`'s `@media print` override, so print
    /// export needs its own fixed-contrast color rather than the live
    /// theme's — applies identically here once Mermaid's SVG output actually
    /// carries theme-driven colors; tracked, not yet applicable while
    /// rendering ignores this context entirely.
    static func mermaidRenderContext(theme: Theme, isPrintTarget _: Bool) -> MermaidRenderContext {
        let foreground = theme.chrome.foreground
        let background = theme.chrome.background
        return MermaidRenderContext(
            foregroundRed: foreground.red,
            foregroundGreen: foreground.green,
            foregroundBlue: foreground.blue,
            backgroundRed: background.red,
            backgroundGreen: background.green,
            backgroundBlue: background.blue
        )
    }
}
