import Foundation

/// The derived content a contribution produced, in whichever shape it was
/// able to express it. This is the "capability metadata" issue #15 asks
/// for: the case a contribution returns is itself the signal a consumer
/// switches on, rather than a separate, redundant metadata field.
public enum ContributionRepresentation: Sendable, Equatable {
    /// Content expressible as Markdown source. Every contribution E14
    /// ships (TOC, the deterministic test contribution) uses this case.
    /// Preview wraps it in a synthetic `PreviewBlock` that Textual
    /// re-parses like any other block; Export renders it to HTML via
    /// `ExportService.renderMarkdownFragment` before splicing.
    case markdown(String)

    /// A self-contained HTML fragment. No contribution in this epic
    /// produces this case, and neither the Preview nor the Export adapter
    /// handles it yet (epic-14-implementation.md §18) — it exists now so a
    /// future contribution whose output cannot round-trip through
    /// Markdown (a rendered equation, an SVG diagram) gets a compiler
    /// error at the adapters instead of a silently ignored case.
    case html(String)
}
