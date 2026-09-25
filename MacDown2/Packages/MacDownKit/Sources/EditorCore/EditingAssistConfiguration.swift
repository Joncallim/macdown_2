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
    /// blockquotes, indentation) and empty-construct termination. Markdown-
    /// specific — `false` for every other format (EPIC-22 §6.11, Slice 4a),
    /// which instead gets a general "maintain the previous line's
    /// indentation" behavior (see `MarkdownEditingAssistEngine+Newline.swift`'s
    /// `generalNewlineOutcome`).
    public var continuesMarkdownPrefixes: Bool

    /// Structural (bracket/quote) pair completion, type-over, selection
    /// wrapping, and paired Backspace — general, format-agnostic mechanics
    /// driven by the active `LanguageEditingProfile.pairedDelimiters`, not
    /// Markdown-specific. Kept under its existing name (a persisted user
    /// setting, `AppSettings.EditorSettings.completesMatchingCharacters`)
    /// rather than renamed, to avoid an unrelated, invasive settings-key
    /// migration — see `completesMarkdownDelimiters` for the Markdown-only
    /// sibling this flag no longer bundles.
    public var completesMatchingCharacters: Bool

    /// Markdown symmetric-delimiter pairing/type-over/wrap/backspace (`*`,
    /// `_`, backtick — bold/italic/inline-code markers). Split out from
    /// `completesMatchingCharacters` (EPIC-22 §6.11, Slice 4a): an
    /// independent hostile review is not the source of this split, but the
    /// same reasoning applies as everywhere else this codebase separates a
    /// general mechanic from a Markdown-specific one — bundling them under
    /// one flag left no way to enable general bracket-pairing for a
    /// non-Markdown format without also offering meaningless
    /// asterisk/underscore/backtick pairing there. `false` for every format
    /// but Markdown.
    public var completesMarkdownDelimiters: Bool

    /// Collapsed Tab inserts spaces to the next indentation stop instead of
    /// inserting a tab character. Selected-line indent also uses spaces.
    /// General — every format.
    public var convertsTabsToSpaces: Bool

    /// Smart Home: first Home press moves to the first non-whitespace
    /// character of the line, second press to the physical line start.
    /// General — every format.
    public var smartHome: Bool

    /// Ordered list continuation increments the number (`1.` → `2.`).
    /// When disabled, the exact digits are repeated. Markdown-specific —
    /// meaningless without `continuesMarkdownPrefixes`.
    public var autoIncrementOrderedLists: Bool

    /// Indentation width in spaces, normalized to `1...8`. The EFFECTIVE
    /// width used by the engine is `LanguageEditingProfile.defaultIndentWidth
    /// ?? indentationWidth` — a format's own profile can override this
    /// global preference; this field is the fallback, not the final word.
    public var indentationWidth: Int

    public init(
        isEnabled: Bool,
        continuesMarkdownPrefixes: Bool = true,
        completesMatchingCharacters: Bool = true,
        completesMarkdownDelimiters: Bool = true,
        convertsTabsToSpaces: Bool = true,
        smartHome: Bool = true,
        autoIncrementOrderedLists: Bool = true,
        indentationWidth: Int = 4
    ) {
        self.isEnabled = isEnabled
        self.continuesMarkdownPrefixes = continuesMarkdownPrefixes
        self.completesMatchingCharacters = completesMatchingCharacters
        self.completesMarkdownDelimiters = completesMarkdownDelimiters
        self.convertsTabsToSpaces = convertsTabsToSpaces
        self.smartHome = smartHome
        self.autoIncrementOrderedLists = autoIncrementOrderedLists
        self.indentationWidth = min(max(1, indentationWidth), 8)
    }

    /// Every assist disabled: the fail-closed default.
    public static let disabled = EditingAssistConfiguration(isEnabled: false)

    /// Markdown-native behavior: all assists on, 4-space indentation.
    public static let markdownDefault = EditingAssistConfiguration(isEnabled: true)

    /// General (non-Markdown) behavior: structural pairing, Tab/Shift-Tab
    /// indent, Smart Home, and generic Return-maintains-indentation all on;
    /// every Markdown-specific behavior off (EPIC-22 §6.11, Slice 4a).
    public static let general = EditingAssistConfiguration(
        isEnabled: true,
        continuesMarkdownPrefixes: false,
        completesMarkdownDelimiters: false,
        autoIncrementOrderedLists: false
    )
}
