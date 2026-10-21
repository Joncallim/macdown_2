import Foundation

/// The derived content a contribution produced. Destination admission is
/// explicit in `ContributionDestination`, rather than inferred from a case.
public enum ContributionRepresentation: Sendable, Equatable {
    /// Content expressible as Markdown source. Every contribution E14
    /// ships (TOC, the deterministic test contribution) uses this case.
    /// Preview wraps it in a synthetic `PreviewBlock` that Textual
    /// re-parses like any other block; Export renders it to HTML via
    /// `ExportService.renderMarkdownFragment` before splicing.
    case markdown(String)

    /// A self-contained first-party HTML fragment for static destinations.
    /// Native Preview cannot admit it as an arbitrary HTML view.
    case html(String)
}
