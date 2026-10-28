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

    /// Generous upper bound for a PERSISTED size (the Settings UI offers 9...36). Without one, a corrupt or foreign
    /// blob could hand NSFont and the Settings pane's integer label a size such as 1e100 (`Int(size)` traps for any
    /// value >= 2^63). An out-of-range blob is unreadable and preserved verbatim like any other invalid one.
    public static let maximumSupportedSize: Double = 1000

    /// The persisted font descriptor is rewritten with these two fields only.
    /// Reject an extra member before decoding so a normal editor save cannot
    /// silently discard a value written by another schema.
    static let admittedStoredKeys: Set<String> = ["familyName", "size"]

    static func admitsStoredObject(_ object: [String: Any]) -> Bool {
        object.keys.allSatisfy(admittedStoredKeys.contains)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let familyName = try container.decode(String.self, forKey: .familyName)
        let size = try container.decode(Double.self, forKey: .size)
        guard size.isFinite, size > 0, size <= Self.maximumSupportedSize else {
            throw DecodingError.dataCorruptedError(
                forKey: .size, in: container,
                debugDescription: "font size must be finite, positive and at most \(Self.maximumSupportedSize)"
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
