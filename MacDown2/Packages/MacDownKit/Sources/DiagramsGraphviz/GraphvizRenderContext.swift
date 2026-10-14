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
        foregroundRed: Double,
        foregroundGreen: Double,
        foregroundBlue: Double,
        backgroundRed: Double,
        backgroundGreen: Double,
        backgroundBlue: Double
    ) {
        self.foregroundRed = 0
        self.foregroundGreen = 0
        self.foregroundBlue = 0
        self.backgroundRed = 1
        self.backgroundGreen = 1
        self.backgroundBlue = 1
    }

    public static let neutralLight = GraphvizRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )
}
