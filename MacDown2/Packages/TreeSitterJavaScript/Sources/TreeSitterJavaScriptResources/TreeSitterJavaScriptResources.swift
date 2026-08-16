import Foundation

/// Resource URLs for the vendored JavaScript grammar.
///
/// `tree-sitter/tree-sitter-javascript` v0.25.0 is the only tag shipping an
/// SPM manifest, and its conditional `src/scanner.c` inclusion is mis-evaluated
/// by SwiftPM 6.x against the bare repository cache (see the root
/// `Package.swift` comment). The grammar is vendored here per
/// `planning/epic-11-implementation.md` §4.10 from the pinned v0.25.0 sources,
/// mirroring the `Packages/TreeSitterMarkdown` pattern.
public enum TreeSitterJavaScriptResources {
    /// The directory containing the `.scm` query files for the JavaScript grammar.
    /// `nil` only if the resource bundle is malformed.
    public static var queriesURL: URL? {
        Bundle.module.url(forResource: "queries", withExtension: nil)
    }
}
