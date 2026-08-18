import Foundation

/// How the export stylesheet is delivered for standalone HTML.
public enum ExportStyleEmbedding: Sendable, Equatable {
    /// CSS is inlined into the document as a `<style>` block.
    case embedded
    /// CSS is written to a companion file and referenced by `<link>`. Only
    /// available for standalone HTML; self-contained and PDF always embed.
    case linked
}

/// The HTML delivery contract. Invalid combinations are unrepresentable:
/// self-contained HTML always embeds CSS and never requests a linked
/// stylesheet; PDF carries no HTML options at all.
public enum HTMLExportMode: Sendable, Equatable {
    /// Ordinary standalone HTML. Authored raw HTML is preserved under the
    /// `CMARK_OPT_UNSAFE + tagfilter` policy, and unresolved or remote
    /// authored references are left in place with a warning.
    case standalone(style: ExportStyleEmbedding)
    /// A single-file HTML document. CSS and every resolvable local resource are
    /// embedded; authored raw HTML is rejected and any unresolved or remote
    /// rendering resource fails the export rather than producing a document
    /// that falsely claims to be self-contained.
    case selfContained
}

/// Where an export lands, and with what options.
///
/// The target owns its destination URL and options; callers cannot supply
/// output layouts, resource roots, production budgets, metadata policies, or
/// template IDs. The HTML and PDF cases deliberately share no option surface:
/// a PDF cannot accidentally carry HTML-only choices.
public enum ExportTarget: Sendable, Equatable {
    case html(url: URL, mode: HTMLExportMode)
    case pdf(url: URL)
}
