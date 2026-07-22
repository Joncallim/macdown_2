import Foundation

/// Resource URLs for the vendored markdown grammar.
public enum TreeSitterMarkdownResources {
    /// The directory containing the `.scm` query files for the block markdown grammar.
    /// `nil` only if the resource bundle is malformed.
    public static var queriesURL: URL? {
        Bundle.module.url(forResource: "queries", withExtension: nil)
    }
}
