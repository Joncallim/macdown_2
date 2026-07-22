import Foundation

/// Canonical highlight capture classes and fallback chain.
public enum HighlightCaptureName {
    /// Trim one trailing dotted segment for fallback: `"keyword.control"` →
    /// `"keyword"`. Returns `nil` at root.
    public static func fallback(_ name: String) -> String? {
        guard let lastDot = name.lastIndex(of: ".") else { return nil }
        return String(name[..<lastDot])
    }

    /// Canonical highlight capture classes the bundled themes style against.
    /// Grammars may emit finer names that fall back to these roots.
    public static let canonical: Set<String> = [
        "keyword",
        "string",
        "comment",
        "number",
        "constant",
        "function",
        "type",
        "variable",
        "property",
        "operator",
        "punctuation",
        "tag",
        "markup.heading",
        "markup.bold",
        "markup.italic",
        "markup.link",
        "markup.raw",
        "markup.list",
        "markup.quote",
        "label",
        "embedded",
    ]
}
