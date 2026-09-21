import Foundation

/// One paired delimiter (opener/closer) available for auto-pairing/type-over
/// in a given `LanguageEditingProfile`. Public mirror of the private
/// `structuralPairs` table `EditingAssistPairs.swift` already uses for
/// Markdown/general bracket-and-quote pairing — kept as a separate public
/// type here so a `LanguageEditingProfile` can be constructed from outside
/// `EditorCore` (e.g. by the app target, when registering a profile for a
/// format `EditorCore` itself has no built-in knowledge of) without
/// exposing the internal table's storage representation.
public struct PairedDelimiter: Sendable, Equatable {
    public let opener: Character
    public let closer: Character

    public init(opener: Character, closer: Character) {
        self.opener = opener
        self.closer = closer
    }

    /// The structural brackets/quotes every text format reasonably wants
    /// (ported from the legacy `kMPMatchingCharactersMap`, same set
    /// `EditingAssistPairs.structuralPairs` already defines for Markdown).
    public static let structural: [PairedDelimiter] = structuralPairs.map { PairedDelimiter(
        opener: $0.opener,
        closer: $0.closer
    ) }
}

/// Editor mechanics for one text format, keyed from `FileFormat.id`/
/// `highlightLanguageID`. Contains only mechanics — comment delimiters,
/// paired delimiters, indentation triggers — never semantic/LSP behavior
/// (no completion, no diagnostics, no go-to-definition).
///
/// This is a pure data type in EPIC-22 Slice 1: it is not yet consumed by
/// `EditorTextSystem`/the editing-assist engine. Slice 4 generalizes the
/// existing Markdown-only pairing/indentation engine to read a profile for
/// every format; until then, constructing one has no observable effect.
public struct LanguageEditingProfile: Sendable, Equatable {
    /// The line-comment prefix, e.g. `"//"` or `"#"`. `nil` if the language
    /// has no single-line comment syntax.
    public var lineComment: String?

    /// The block-comment open/close pair, e.g. `("/*", "*/")`. `nil` if the
    /// language has no block-comment syntax.
    public var blockComment: BlockCommentDelimiters?

    /// Delimiters this format auto-pairs/type-overs, beyond whatever the
    /// general structural set already provides. A format that wants exactly
    /// `PairedDelimiter.structural` and nothing else may leave this at the
    /// default.
    public var pairedDelimiters: [PairedDelimiter]

    /// Characters after which Return indents the new line one level
    /// further (e.g. `{` for C-family languages).
    public var indentAfterTrailing: Set<Character>

    /// Per-format indentation-width override. `nil` defers to the global
    /// `EditorSettings.indentationWidth` value.
    public var defaultIndentWidth: Int?

    public init(
        lineComment: String? = nil,
        blockComment: BlockCommentDelimiters? = nil,
        pairedDelimiters: [PairedDelimiter] = PairedDelimiter.structural,
        indentAfterTrailing: Set<Character> = [],
        defaultIndentWidth: Int? = nil
    ) {
        self.lineComment = lineComment
        self.blockComment = blockComment
        self.pairedDelimiters = pairedDelimiters
        self.indentAfterTrailing = indentAfterTrailing
        self.defaultIndentWidth = defaultIndentWidth
    }

    /// No comment syntax, no extra indent triggers, only the general
    /// structural pairs — the safe default for a format with no specific
    /// profile registered (e.g. plain text).
    public static let plainText = LanguageEditingProfile()
}

public struct BlockCommentDelimiters: Sendable, Equatable {
    public let open: String
    public let close: String

    public init(open: String, close: String) {
        self.open = open
        self.close = close
    }
}
