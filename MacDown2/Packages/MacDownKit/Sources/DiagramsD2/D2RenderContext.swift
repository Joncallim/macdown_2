import Foundation

/// Theme inputs, mirroring `MermaidRenderContext`'s shape. Not yet acted
/// on by `D2WebRenderer` — same disclosed, deliberate scope limit already
/// recorded for Mermaid (issue #79); not solved for D2/Graphviz here
/// either (epic-21-implementation.md §6 Definition of Done).
public struct D2RenderContext: Sendable, Equatable, Hashable {
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
        self.foregroundRed = foregroundRed
        self.foregroundGreen = foregroundGreen
        self.foregroundBlue = foregroundBlue
        self.backgroundRed = backgroundRed
        self.backgroundGreen = backgroundGreen
        self.backgroundBlue = backgroundBlue
    }
}
