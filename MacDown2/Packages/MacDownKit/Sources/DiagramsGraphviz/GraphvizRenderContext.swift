import Themes

/// A resolved diagram policy, independent of the surrounding app theme.
public struct GraphvizRenderContext: Sendable, Equatable, Hashable {
    public let palette: DiagramPalette

    public init(palette: DiagramPalette = .neutralLight) {
        self.palette = palette
    }

    /// Legacy component inputs intentionally resolve to the fixed policy.
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

    public static let neutralLight = GraphvizRenderContext()
}
