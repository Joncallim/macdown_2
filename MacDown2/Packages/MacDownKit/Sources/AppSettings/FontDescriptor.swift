import Foundation

/// A serializable stand-in for `NSFont`, which is not `Codable`.
///
/// Conversion to/from `NSFont` happens only at the AppKit boundary in the
/// app target (mirrors how `Themes.ThemeColor` bridges to `NSColor` only
/// through a computed property, never storing AppKit types directly).
public struct FontDescriptor: Codable, Sendable, Equatable {
    public var familyName: String
    public var size: Double

    private enum CodingKeys: String, CodingKey {
        case familyName, size
    }

    public init(familyName: String, size: Double) {
        self.familyName = familyName
        self.size = size
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let familyName = try container.decode(String.self, forKey: .familyName)
        let size = try container.decode(Double.self, forKey: .size)
        guard size.isFinite, size > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .size, in: container, debugDescription: "font size must be finite and positive"
            )
        }
        self.init(familyName: familyName, size: size)
    }

    /// Matches `EditorConfiguration.default`'s font
    /// (`NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight:
    /// .regular)`) by family name, so this module can define the default
    /// without importing AppKit.
    public static let systemMonospacedDefault = FontDescriptor(familyName: "SF Mono", size: 13)
}
