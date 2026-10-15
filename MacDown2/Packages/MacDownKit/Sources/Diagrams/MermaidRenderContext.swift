import Foundation

/// Fixed neutral-light Mermaid policy. The component-shaped initializer stays
/// source-compatible, but app-theme colors are deliberately ignored.
public struct MermaidRenderContext: Sendable, Equatable, Hashable {
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
        foregroundRed = 0x1A / 255.0
        foregroundGreen = 0x1A / 255.0
        foregroundBlue = 0x1A / 255.0
        backgroundRed = 1
        backgroundGreen = 1
        backgroundBlue = 1
    }

    public static let neutralLight = MermaidRenderContext(
        foregroundRed: 0x1A / 255.0, foregroundGreen: 0x1A / 255.0, foregroundBlue: 0x1A / 255.0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )
}
