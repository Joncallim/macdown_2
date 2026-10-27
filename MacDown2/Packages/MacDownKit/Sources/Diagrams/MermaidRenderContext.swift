import Themes

/// A resolved diagram policy, independent of the surrounding app theme.
public struct MermaidRenderContext: Sendable, Equatable, Hashable {
    public let palette: DiagramPalette

    public init(palette: DiagramPalette = .neutralLight) {
        self.palette = palette
    }

    /// Preserve callers of the earlier component API without allowing an
    /// app theme to change first-party diagram defaults.
    public init(
        foregroundRed _: Double,
        foregroundGreen _: Double,
        foregroundBlue _: Double,
        backgroundRed _: Double,
        backgroundGreen _: Double,
        backgroundBlue _: Double
    ) {
        palette = .neutralLight
    }

    public static let neutralLight = MermaidRenderContext()
}
