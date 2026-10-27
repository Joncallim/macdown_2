import Themes

/// Resolved artwork defaults and destination, shared by preview and export.
public struct D2RenderContext: Sendable, Equatable, Hashable {
    public let palette: DiagramPalette
    public let destination: DiagramDestination

    public var fingerprint: String {
        destination.rawValue + "|" + palette.fingerprint
    }

    public init(palette: DiagramPalette = .neutralLight, destination: DiagramDestination = .print) {
        self.palette = palette
        self.destination = destination
    }

    /// Component callers describe screen preview colors.
    public init(
        foregroundRed: Double,
        foregroundGreen: Double,
        foregroundBlue: Double,
        backgroundRed: Double,
        backgroundGreen: Double,
        backgroundBlue: Double
    ) {
        destination = .screen
        palette = .resolved(
            for: .screen,
            foreground: ThemeColor(red: foregroundRed, green: foregroundGreen, blue: foregroundBlue),
            background: ThemeColor(red: backgroundRed, green: backgroundGreen, blue: backgroundBlue)
        )
    }

    public static let neutralLight = D2RenderContext()
}
