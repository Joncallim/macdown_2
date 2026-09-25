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

    /// `true` exactly for the Markdown format (EPIC-22 §6.11, Slice 4a).
    /// Independent of `continuesMarkdownPrefixes` on purpose: an independent
    /// hostile review of this slice found that dispatching Return's own
    /// Markdown-vs-general behavior off `continuesMarkdownPrefixes` alone
    /// conflated two different questions — "is this document Markdown" and
    /// "did the user turn off list/quote/indentation continuation" — which
    /// are both represented by that one flag being `false` for a
    /// non-Markdown document, but need to be told apart for a MARKDOWN
    /// document whose user has turned continuation off via its own real,
    /// persisted Preferences toggle ("Continue lists, quotes, and
    /// indentation on Return"): before this slice, that toggle made Return
    /// a pure no-op for Markdown, full stop; without this separate flag, the
    /// new general "maintain indentation" behavior this slice added would
    /// have silently resurrected indentation-carrying for exactly the users
    /// who explicitly asked to turn it off — the toggle's own label promises
    /// "...and indentation," not just list markers.
    public var isMarkdownFormat: Bool

    /// Return-key continuation of Markdown line prefixes (lists, task lists,
    /// blockquotes, indentation) and empty-construct termination. Meaningful
    /// only when `isMarkdownFormat` is `true`; a non-Markdown format's
    /// configuration leaves this at its default and it is never consulted
    /// (see `isMarkdownFormat`'s own doc comment for why the two are
    /// deliberately independent). When `false` for a Markdown document,
    /// Return is a pure no-op here — the general "maintain the previous
    /// line's indentation" behavior
    /// (`MarkdownEditingAssistEngine+Newline.swift`'s `generalNewlineOutcome`)
    /// is reserved for non-Markdown formats only.
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
        isMarkdownFormat: Bool = true,
        continuesMarkdownPrefixes: Bool = true,
        completesMatchingCharacters: Bool = true,
        completesMarkdownDelimiters: Bool = true,
        convertsTabsToSpaces: Bool = true,
        smartHome: Bool = true,
        autoIncrementOrderedLists: Bool = true,
        indentationWidth: Int = 4
    ) {
        self.isEnabled = isEnabled
        self.isMarkdownFormat = isMarkdownFormat
        self.continuesMarkdownPrefixes = continuesMarkdownPrefixes
        self.completesMatchingCharacters = completesMatchingCharacters
        self.completesMarkdownDelimiters = completesMarkdownDelimiters
        self.convertsTabsToSpaces = convertsTabsToSpaces
        self.smartHome = smartHome
        self.autoIncrementOrderedLists = autoIncrementOrderedLists
        self.indentationWidth = min(max(1, indentationWidth), 8)
    }

    /// Every assist disabled: the fail-closed default. `isMarkdownFormat`'s
    /// own default (`true`) is irrelevant here since `isEnabled` short-
    /// circuits the whole engine before anything reads it.
    public static let disabled = EditingAssistConfiguration(isEnabled: false)

    /// Markdown-native behavior: all assists on, 4-space indentation.
    public static let markdownDefault = EditingAssistConfiguration(isEnabled: true, isMarkdownFormat: true)

    /// General (non-Markdown) behavior: structural pairing, Tab/Shift-Tab
    /// indent, Smart Home, and generic Return-maintains-indentation all on;
    /// every Markdown-specific behavior off (EPIC-22 §6.11, Slice 4a).
    public static let general = EditingAssistConfiguration(
        isEnabled: true,
        isMarkdownFormat: false,
        continuesMarkdownPrefixes: false,
        completesMarkdownDelimiters: false,
        autoIncrementOrderedLists: false
    )
}
