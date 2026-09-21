/// TextSearch module namespace.
///
/// Owns search/index/fuzzy-scoring as pure, UI-free, Foundation-only types
/// shared by current-document find (EPIC-22 Slice 5) and workspace-wide
/// folder search (Slice 6/7). Depends only on FileCore + Foundation — no
/// AppKit, SwiftUI, window, or tab knowledge (see
/// `planning/epic-22-implementation.md` §5.1).
///
/// Concrete types live in the sibling files in this module.
public enum TextSearch {
    public static let moduleName = "TextSearch"
}
