import Foundation

/// Resource URLs for the vendored markdown inline grammar.
public enum TreeSitterMarkdownInlineResources {
    /// The directory containing the `.scm` query files for the inline markdown grammar.
    /// `nil` only if the resource bundle is malformed.
    public static var queriesURL: URL? {
        Bundle.module.url(forResource: "queries", withExtension: nil)
    }
}
