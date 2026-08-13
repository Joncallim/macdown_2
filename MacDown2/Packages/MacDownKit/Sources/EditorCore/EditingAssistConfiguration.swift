import Foundation

/// Typed configuration for E10 editing assists.
///
/// The struct is `Sendable` and `Equatable` so it can flow through
/// `EditorConfiguration` (diffed by `EditorTextSystem.apply(_:)`) without
/// coupling to AppKit objects.
public struct EditingAssistConfiguration: Sendable, Equatable {
    /// Master switch. When `false`, every assist decision falls through to
    /// native AppKit behavior.
    public var isEnabled: Bool

    /// Return-key continuation of Markdown line prefixes (lists, task lists,
    /// blockquotes, indentation) and empty-construct termination.
    public var continuesMarkdownPrefixes: Bool

    /// Structural pair completion, Markdown symmetric delimiter pairing,
    /// type-over, selection wrapping, and paired Backspace.
    public var completesMatchingCharacters: Bool

    /// Collapsed Tab inserts spaces to the next indentation stop instead of
    /// inserting a tab character. Selected-line indent also uses spaces.
    public var convertsTabsToSpaces: Bool

    /// Smart Home: first Home press moves to the first non-whitespace
    /// character of the line, second press to the physical line start.
    public var smartHome: Bool

    /// Ordered list continuation increments the number (`1.` → `2.`).
    /// When disabled, the exact digits are repeated.
    public var autoIncrementOrderedLists: Bool

    /// Indentation width in spaces, normalized to `1...8`.
    public var indentationWidth: Int

    public init(
        isEnabled: Bool,
        continuesMarkdownPrefixes: Bool = true,
        completesMatchingCharacters: Bool = true,
        convertsTabsToSpaces: Bool = true,
        smartHome: Bool = true,
        autoIncrementOrderedLists: Bool = true,
        indentationWidth: Int = 4
    ) {
        self.isEnabled = isEnabled
        self.continuesMarkdownPrefixes = continuesMarkdownPrefixes
        self.completesMatchingCharacters = completesMatchingCharacters
        self.convertsTabsToSpaces = convertsTabsToSpaces
        self.smartHome = smartHome
        self.autoIncrementOrderedLists = autoIncrementOrderedLists
        self.indentationWidth = min(max(1, indentationWidth), 8)
    }

    /// Every assist disabled: the fail-closed default.
    public static let disabled = EditingAssistConfiguration(isEnabled: false)

    /// Markdown-native behavior: all assists on, 4-space indentation.
    public static let markdownDefault = EditingAssistConfiguration(isEnabled: true)
}
