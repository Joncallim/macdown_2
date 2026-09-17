import Contributions
import Diagrams
import DiagramsD2
import DiagramsGraphviz
import Foundation
import Math
import MathRendering
import Themes

/// Registers `MathContribution`, `MermaidContribution`, `D2Contribution`,
/// and `GraphvizContribution` for Export only, never for Preview
/// (epic-19-implementation.md §4 invariant 5, §6.3; epic-20-implementation.md
/// §2.2; epic-21-implementation.md §3.6): Preview's math rendering goes
/// through `Textual`'s own `.math` syntax extension directly on each
/// block's literal source text, and Preview's diagram rendering goes
/// through dedicated native views — none of these go through
/// `ContributionRegistry`. `PreviewContributionAdmission` already rejects
/// `.html` representations with a visible error badge — routing any of
/// these through the SHARED `ContributionRegistry.standard` that Preview
/// also uses would put that rejection badge on every affected document, a
/// real regression this separate, Export-only factory avoids. Each
/// language's own supporting pieces (shared renderer/cache instance,
/// context derivation) live in that language's own `*ExportRegistry.swift`
/// file; this file keeps ownership of the one real `standardForExport`
/// factory function so there is exactly one place export contributions are
/// assembled, not a competing registry per language.
extension ContributionRegistry {
    /// `ExportService`'s own `structural.css` overrides EVERY theme's
    /// foreground/background for `@media print` — "Paper is white. A dark
    /// theme's foreground would print as light text on a white page... so
    /// print gets its own readable palette" (`structural.css`, `@media
    /// print` block). Ordinary themed body text is safe because that CSS
    /// override applies to it live; a math equation is a pre-baked PNG of
    /// fixed pixel colors that CSS cannot recolor after the fact — found
    /// during this epic's own adversarial review (a dark theme's light
    /// foreground, baked into an equation image, would print as
    /// near-invisible light-gray-on-white). `isPrintTarget` therefore
    /// selects the identical fixed color `structural.css` uses for print
    /// (`#1a1a1a`) instead of the live theme's foreground when rendering
    /// for PDF; this constant must stay in sync with that CSS file's own
    /// `--md-foreground` print value.
    private static let printSafeForegroundComponent = 0x1A as Double / 255.0

    static func standardForExport(theme: Theme, isPrintTarget: Bool) -> ContributionRegistry {
        let context = mathRenderContext(theme: theme, isPrintTarget: isPrintTarget)
        let mermaidContext = mermaidRenderContext(theme: theme, isPrintTarget: isPrintTarget)
        let d2Context = d2RenderContext(theme: theme, isPrintTarget: isPrintTarget)
        let graphvizContext = graphvizRenderContext(theme: theme, isPrintTarget: isPrintTarget)
        return ContributionRegistry(contributions: [
            TOCContribution(),
            MathContribution(context: context, renderer: MathImageRenderer.render(span:context:)),
            MermaidContribution(context: mermaidContext, renderer: sharedMermaidRenderer),
            D2Contribution(context: d2Context, renderer: sharedD2Renderer),
            GraphvizContribution(context: graphvizContext, renderer: sharedGraphvizRenderer),
        ])
    }

    /// Split out from `standardForExport` so the color-selection rule
    /// itself is directly unit-testable without inspecting a constructed
    /// `MathContribution`'s private state.
    static func mathRenderContext(theme: Theme, isPrintTarget: Bool) -> ExportMathRenderContext {
        if isPrintTarget {
            return ExportMathRenderContext(
                foregroundRed: printSafeForegroundComponent,
                foregroundGreen: printSafeForegroundComponent,
                foregroundBlue: printSafeForegroundComponent,
                pixelScale: MathImageRenderer.standardScale
            )
        }
        let foreground = theme.chrome.foreground
        return ExportMathRenderContext(
            foregroundRed: foreground.red,
            foregroundGreen: foreground.green,
            foregroundBlue: foreground.blue,
            pixelScale: MathImageRenderer.standardScale
        )
    }
}
