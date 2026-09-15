import Foundation

/// Theme inputs that affect rendering but are not part of the diagram source
/// itself (epic-20-implementation.md §6). Unlike `ExportMathRenderContext`,
/// carries no pixel scale: SVG is resolution-independent, so scale is a
/// display-time concern, not a render-time one.
public struct MermaidRenderContext: Sendable, Equatable, Hashable {
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
