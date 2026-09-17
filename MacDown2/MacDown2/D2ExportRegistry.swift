import Contributions
import D2Rendering
import DiagramsD2
import Foundation
import Themes

/// D2-specific supporting pieces for `ContributionRegistry.standardForExport`
/// (`MathExportRegistry.swift`, which owns the one real factory function —
/// see that file for why `D2Contribution` is registered for Export only,
/// never for Preview). Mirrors `MermaidExportRegistry.swift`'s exact shape.
extension ContributionRegistry {
    /// One process-lifetime, shared renderer/cache instance backs both
    /// Export (`standardForExport`) and Preview (Slice 4) — a diagram
    /// already rendered for one is not re-rendered for the other.
    static let sharedD2Renderer = D2DiagramCache(renderer: D2WebRenderer())

    /// `D2WebRenderer.render`'s `context` parameter is not yet wired to
    /// D2's own theming — same disclosed, deliberate scope limit already
    /// recorded for Mermaid (issue #79).
    static func d2RenderContext(theme: Theme, isPrintTarget _: Bool) -> D2RenderContext {
        let foreground = theme.chrome.foreground
        let background = theme.chrome.background
        return D2RenderContext(
            foregroundRed: foreground.red,
            foregroundGreen: foreground.green,
            foregroundBlue: foreground.blue,
            backgroundRed: background.red,
            backgroundGreen: background.green,
            backgroundBlue: background.blue
        )
    }
}
