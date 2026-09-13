import CoreGraphics
import Foundation

/// What `MathContribution` gives its injected renderer beyond one
/// `MathSpan` — the theme foreground color and target pixel scale, both
/// fixed for one export (a single `Theme` and a single `standardScale`
/// apply to every equation in the same export request), so these are
/// threaded in once at `MathContribution.init`, not re-derived per call
/// (epic-19-implementation.md §6.2).
///
/// Color is plain 0...1 RGB components — matching `Themes.ThemeColor`'s own
/// shape exactly — rather than a hex string: `Math` (this package) has no
/// dependency on `Themes` (§5's ownership boundary), so it cannot construct
/// or parse a `ThemeColor` itself; the app-layer wiring that builds this
/// context converts a real `ThemeColor` into these three `Double`s, and
/// `MathRendering`'s `MathImageRenderer` converts them straight into a
/// SwiftUI `Color` with no lossy hex round-trip in between.
public struct ExportMathRenderContext: Sendable, Equatable {
    public let foregroundRed: Double
    public let foregroundGreen: Double
    public let foregroundBlue: Double

    public let pixelScale: CGFloat

    public init(foregroundRed: Double, foregroundGreen: Double, foregroundBlue: Double, pixelScale: CGFloat) {
        self.foregroundRed = foregroundRed
        self.foregroundGreen = foregroundGreen
        self.foregroundBlue = foregroundBlue
        self.pixelScale = pixelScale
    }
}
