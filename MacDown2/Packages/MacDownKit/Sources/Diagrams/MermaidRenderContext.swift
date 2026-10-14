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
        foregroundRed: Double,
        foregroundGreen: Double,
        foregroundBlue: Double,
        backgroundRed: Double,
        backgroundGreen: Double,
        backgroundBlue: Double
    ) {
        self.foregroundRed = 0x1A / 255.0
        self.foregroundGreen = 0x1A / 255.0
        self.foregroundBlue = 0x1A / 255.0
        self.backgroundRed = 1
        self.backgroundGreen = 1
        self.backgroundBlue = 1
    }

    public static let neutralLight = MermaidRenderContext(
        foregroundRed: 0x1A / 255.0, foregroundGreen: 0x1A / 255.0, foregroundBlue: 0x1A / 255.0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )
}
