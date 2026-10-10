import Foundation

/// Editor typography and E10 editing-assist preferences.
///
/// Reproduces `EditorCore.EditorConfiguration.default` and
/// `EditingAssistConfiguration.markdownDefault`'s current values exactly, so
/// shipping this type changes no observable behavior until a user opens
/// Settings and changes something (see epic-13-implementation.md §3, J5).
public struct EditorSettings: Codable, Sendable, Equatable {
    public var font: FontDescriptor
    public var wrapsLines: Bool
    public var showsInvisibles: Bool
    public var showsStatusBar: Bool
    /// Clamped to `1...8`, matching `EditingAssistConfiguration.indentationWidth`.
    public var indentationWidth: Int
    /// Maps to `EditingAssistConfiguration.isEnabled`, the master switch.
    public var assistsEnabled: Bool
    public var continuesMarkdownPrefixes: Bool
    public var completesMatchingCharacters: Bool
    public var convertsTabsToSpaces: Bool
    public var smartHome: Bool
    public var autoIncrementOrderedLists: Bool

    public init(
        font: FontDescriptor = .systemMonospacedDefault,
        wrapsLines: Bool = true,
        showsInvisibles: Bool = false,
        showsStatusBar: Bool = true,
        indentationWidth: Int = 4,
        assistsEnabled: Bool = true,
        continuesMarkdownPrefixes: Bool = true,
        completesMatchingCharacters: Bool = true,
        convertsTabsToSpaces: Bool = true,
        smartHome: Bool = true,
        autoIncrementOrderedLists: Bool = true
    ) {
        self.font = font
        self.wrapsLines = wrapsLines
        self.showsInvisibles = showsInvisibles
        self.showsStatusBar = showsStatusBar
        self.indentationWidth = min(max(1, indentationWidth), 8)
        self.assistsEnabled = assistsEnabled
        self.continuesMarkdownPrefixes = continuesMarkdownPrefixes
        self.completesMatchingCharacters = completesMatchingCharacters
        self.convertsTabsToSpaces = convertsTabsToSpaces
        self.smartHome = smartHome
        self.autoIncrementOrderedLists = autoIncrementOrderedLists
    }

    public static let `default` = EditorSettings()

    private enum CodingKeys: String, CodingKey {
        case font, wrapsLines, showsInvisibles, showsStatusBar, indentationWidth, assistsEnabled
        case continuesMarkdownPrefixes, completesMatchingCharacters, convertsTabsToSpaces
        case smartHome, autoIncrementOrderedLists
    }

    /// Compatible decoding (#53). The historical schema-less blob lacks fields added later: those, and ONLY those,
    /// take their documented default when absent (`showsStatusBar` is `true` when missing, but a present `false`
    /// stays `false`). Every field that has always existed is required, and the clamped `indentationWidth` is
    /// range-validated here because synthesized `Decodable` never runs the initializer's clamp: an out-of-range or
    /// mistyped value is a corrupt blob (kept and reported by the store), not something to silently coerce.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        font = try container.decode(FontDescriptor.self, forKey: .font)
        wrapsLines = try container.decode(Bool.self, forKey: .wrapsLines)
        showsInvisibles = try container.decode(Bool.self, forKey: .showsInvisibles)
        showsStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showsStatusBar) ?? true
        let width = try container.decode(Int.self, forKey: .indentationWidth)
        guard (1 ... 8).contains(width) else {
            throw DecodingError.dataCorruptedError(
                forKey: .indentationWidth, in: container, debugDescription: "indentationWidth must be 1...8"
            )
        }
        indentationWidth = width
        assistsEnabled = try container.decode(Bool.self, forKey: .assistsEnabled)
        continuesMarkdownPrefixes = try container.decode(Bool.self, forKey: .continuesMarkdownPrefixes)
        completesMatchingCharacters = try container.decode(Bool.self, forKey: .completesMatchingCharacters)
        convertsTabsToSpaces = try container.decode(Bool.self, forKey: .convertsTabsToSpaces)
        smartHome = try container.decode(Bool.self, forKey: .smartHome)
        autoIncrementOrderedLists = try container.decode(Bool.self, forKey: .autoIncrementOrderedLists)
    }
}
