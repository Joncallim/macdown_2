import Foundation

/// Fixed neutral-light policy for Graphviz. The legacy component-shaped
/// initializer remains source-compatible, but app-theme colors are deliberately
/// ignored because Graphviz artwork uses native defaults on an opaque white
/// canvas.
public struct GraphvizRenderContext: Sendable, Equatable, Hashable {
    public let foregroundRed: Double
    public let foregroundGreen: Double
    public let foregroundBlue: Double
    public let backgroundRed: Double
    public let backgroundGreen: Double
    public let backgroundBlue: Double

    public init(
        foregroundRed _: Double,
        foregroundGreen _: Double,
        foregroundBlue _: Double,
        backgroundRed _: Double,
        backgroundGreen _: Double,
        backgroundBlue _: Double
    ) {
        foregroundRed = 0
        foregroundGreen = 0
        foregroundBlue = 0
        backgroundRed = 1
        backgroundGreen = 1
        backgroundBlue = 1
    }

    public static let neutralLight = GraphvizRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )
}
