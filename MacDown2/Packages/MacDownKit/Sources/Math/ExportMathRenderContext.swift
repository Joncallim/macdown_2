import CoreGraphics
import Foundation

/// What `MathContribution` gives its injected renderer beyond one
/// `MathSpan` — the theme foreground color and target pixel scale, both
/// fixed for one export (a single `Theme` and a single `standardScale`
/// apply to every equation in the same export request), so these are
/// threaded in once at `MathContribution.init`, not re-derived per call
/// (epic-19-implementation.md §6.2).
public struct ExportMathRenderContext: Sendable, Equatable {
    /// e.g. `"#1a1a1a"` — matches `ExportURLPolicy`'s existing
    /// string-based color convention rather than introducing a new color
    /// type into this package.
    public let foregroundHex: String

    public let pixelScale: CGFloat

    public init(foregroundHex: String, pixelScale: CGFloat) {
        self.foregroundHex = foregroundHex
        self.pixelScale = pixelScale
    }
}
