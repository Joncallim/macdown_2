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
        self.indentationWidth = min(max(1, indentationWidth), 8)
        self.assistsEnabled = assistsEnabled
        self.continuesMarkdownPrefixes = continuesMarkdownPrefixes
        self.completesMatchingCharacters = completesMatchingCharacters
        self.convertsTabsToSpaces = convertsTabsToSpaces
        self.smartHome = smartHome
        self.autoIncrementOrderedLists = autoIncrementOrderedLists
    }

    public static let `default` = EditorSettings()
}
