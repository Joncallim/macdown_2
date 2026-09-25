import Foundation

/// Hand-authored `LanguageEditingProfile` per registered `FileFormat.id`
/// (EPIC-22 §6.11, Slice 4a). `EditorCore` has no dependency on `FileCore`'s
/// `FileFormat` type for this — matching `LanguageEditingProfile`'s own doc
/// comment, formats are keyed by their plain string id, the same convention
/// `highlightLanguageID` already uses elsewhere in this codebase.
///
/// Every format not listed here falls back to `.plainText` — general
/// structural pairing only, no comment syntax, no indent-after-trailing
/// triggers. This is a disclosed, reasonable set of per-language defaults
/// (comment delimiters, indent-after-trailing brace/colon characters), not a
/// claim of exhaustive per-language correctness; a wrong or missing entry
/// degrades gracefully to `.plainText`'s safe behavior, never a crash or a
/// destructive edit.
public enum LanguageEditingProfileRegistry {
    public static func profile(for formatID: String) -> LanguageEditingProfile {
        profiles[formatID] ?? .plainText
    }

    private static let htmlStyleComment = BlockCommentDelimiters(open: "<!--", close: "-->")
    private static let cStyleComment = BlockCommentDelimiters(open: "/*", close: "*/")

    private static let profiles: [String: LanguageEditingProfile] = [
        // Markdown's own list/blockquote/symmetric-delimiter behavior is
        // handled entirely outside this profile (still gated on
        // `EditingAssistConfiguration.continuesMarkdownPrefixes`/
        // `completesMarkdownDelimiters`) — this is only its GENERAL
        // mechanics: structural pairing (the default), and the block-comment
        // syntax a Markdown comment-toggle command (Slice 4c) would use for
        // prose outside a fenced code block, since Markdown has no
        // conventional line-comment syntax of its own.
        "markdown": LanguageEditingProfile(blockComment: htmlStyleComment),
        "html": LanguageEditingProfile(blockComment: htmlStyleComment),
        "xml": LanguageEditingProfile(blockComment: htmlStyleComment),
        "json": LanguageEditingProfile(indentAfterTrailing: ["{", "["]),
        "yaml": LanguageEditingProfile(lineComment: "#"),
        "toml": LanguageEditingProfile(lineComment: "#"),
        "javascript": LanguageEditingProfile(
            lineComment: "//",
            blockComment: cStyleComment,
            indentAfterTrailing: ["{", "["]
        ),
        "typescript": LanguageEditingProfile(
            lineComment: "//",
            blockComment: cStyleComment,
            indentAfterTrailing: ["{", "["]
        ),
        "python": LanguageEditingProfile(lineComment: "#", indentAfterTrailing: [":"]),
        "ruby": LanguageEditingProfile(lineComment: "#"),
        "css": LanguageEditingProfile(blockComment: cStyleComment, indentAfterTrailing: ["{"]),
        "swift": LanguageEditingProfile(
            lineComment: "//",
            blockComment: cStyleComment,
            indentAfterTrailing: ["{", "["]
        ),
        "c": LanguageEditingProfile(lineComment: "//", blockComment: cStyleComment, indentAfterTrailing: ["{"]),
        "bash": LanguageEditingProfile(lineComment: "#"),
        "sql": LanguageEditingProfile(lineComment: "--"),
        "plaintext": .plainText,
    ]
}
