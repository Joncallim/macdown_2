import Foundation

/// Resource URLs for the vendored SQL grammar.
///
/// `DerekStride/tree-sitter-sql` does not check its generated `parser.c` into
/// the repository (`.gitignore` excludes it), so its upstream SPM package
/// cannot build from source. The grammar is vendored here per
/// `planning/epic-11-implementation.md` §4.10: `parser.c` is generated from
/// the pinned `grammar.js` (commit `c2e1e08`) with the tree-sitter CLI, and
/// the queries ship in this resources target.
public enum TreeSitterSQLResources {
    /// The directory containing the `.scm` query files for the SQL grammar.
    /// `nil` only if the resource bundle is malformed.
    public static var queriesURL: URL? {
        Bundle.module.url(forResource: "queries", withExtension: nil)
    }
}
