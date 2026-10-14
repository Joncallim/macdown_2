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
    private static let printSafeForegroundComponent = 0x1A as Double / 255.0

    /// One process-lifetime, shared renderer/cache instance backs both
    /// Export (`standardForExport`) and Preview (`MermaidPreviewRenderer`,
    /// Slice 4) — a diagram already rendered for one is not re-rendered for
    /// the other, per the cache's own content-addressed keying
    /// (`MermaidDiagramCache`, epic-20-implementation.md §5).
    static let sharedMermaidRenderer = MermaidDiagramCache(renderer: MermaidWebRenderer())

    /// The export path derives its Mermaid context here so print output does
    /// not inherit light-on-dark colors from the live editor theme. Live
    /// preview keeps the colors from the active editor theme.
    static func mermaidRenderContext(theme: Theme, isPrintTarget: Bool) -> MermaidRenderContext {
        if isPrintTarget {
            return MermaidRenderContext(
                foregroundRed: printSafeForegroundComponent,
                foregroundGreen: printSafeForegroundComponent,
                foregroundBlue: printSafeForegroundComponent,
                backgroundRed: 1,
                backgroundGreen: 1,
                backgroundBlue: 1
            )
        }
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
