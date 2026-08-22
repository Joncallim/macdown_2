import Foundation

/// A serializable stand-in for `NSFont`, which is not `Codable`.
///
/// Conversion to/from `NSFont` happens only at the AppKit boundary in the
/// app target (mirrors how `Themes.ThemeColor` bridges to `NSColor` only
/// through a computed property, never storing AppKit types directly).
public struct FontDescriptor: Codable, Sendable, Equatable {
    public var familyName: String
    public var size: Double

    public init(familyName: String, size: Double) {
        self.familyName = familyName
        self.size = size
    }

    /// Matches `EditorConfiguration.default`'s font
    /// (`NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight:
    /// .regular)`) by family name, so this module can define the default
    /// without importing AppKit.
    public static let systemMonospacedDefault = FontDescriptor(familyName: "SF Mono", size: 13)
}
