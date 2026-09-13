import Contributions
import Foundation
import Math
import MathRendering
import Themes

/// Registers `MathContribution` for Export only, never for Preview
/// (epic-19-implementation.md §4 invariant 5, §6.3): Preview's math
/// rendering goes through `Textual`'s own `.math` syntax extension directly
/// on each block's literal source text, not through `ContributionRegistry`.
/// `PreviewContributionAdmission` already rejects `.html` representations
/// with a visible error badge — routing `MathContribution` through the
/// SHARED `ContributionRegistry.standard` that Preview also uses would put
/// that rejection badge on every math-containing document, a real
/// regression this separate factory avoids.
extension ContributionRegistry {
    static func standardForExport(theme: Theme) -> ContributionRegistry {
        let foreground = theme.chrome.foreground
        let context = ExportMathRenderContext(
            foregroundRed: foreground.red,
            foregroundGreen: foreground.green,
            foregroundBlue: foreground.blue,
            pixelScale: MathImageRenderer.standardScale
        )
        return ContributionRegistry(contributions: [
            TOCContribution(),
            MathContribution(context: context, renderer: MathImageRenderer.render(span:context:)),
        ])
    }
}
