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

    /// Resolve defaults before rendering; explicit source styles remain authored.
    static func d2RenderContext(theme: Theme, isPrintTarget: Bool) -> D2RenderContext {
        let destination: DiagramDestination = isPrintTarget ? .print : .screen
        return D2RenderContext(
            palette: .resolved(
                for: destination,
                foreground: theme.chrome.foreground,
                background: theme.chrome.background
            ),
            destination: destination
        )
    }
}
