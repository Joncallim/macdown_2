import Foundation

/// The frozen result of export composition: everything needed to render HTML or
/// feed the PDF adapter, with no further composition decisions left to make.
///
/// `bodyHTML` is the cmark-rendered body fragment. Resource references in it
/// have already been rewritten to their content-addressed companion form
/// (`report.assets/<64hex>.<ext>`); the HTML writers either keep that form
/// (companion output) or embed the bytes as data URIs (self-contained/PDF).
public struct PreparedExportDocument: Sendable, Equatable {
    /// The browser title: front matter's `title`, else the saved filename stem,
    /// else empty (in which case no `<title>` element is emitted).
    public let title: String

    /// The heading rendered at the top of the document. Present only when front
    /// matter supplied a title; a filename fallback is never a visible heading.
    public let visibleTitle: String?

    /// The rendered Markdown body, with derived content and resource references
    /// resolved to companion form.
    public let bodyHTML: String

    /// The combined stylesheet: structural CSS + the theme variable block.
    public let stylesheet: String

    /// The frozen resource manifest.
    public let manifest: ExportManifest

    /// Composition diagnostics (warnings and errors), never silently dropped.
    public let diagnostics: [ExportDiagnostic]

    /// The `FileDocument.mutationGeneration` of the source snapshot.
    public let sourceGeneration: UInt

    /// `true` when authored raw HTML was preserved (`CMARK_OPT_UNSAFE`).
    public let preservesRawHTML: Bool

    public init(
        title: String,
        visibleTitle: String? = nil,
        bodyHTML: String,
        stylesheet: String,
        manifest: ExportManifest,
        diagnostics: [ExportDiagnostic],
        sourceGeneration: UInt,
        preservesRawHTML: Bool
    ) {
        self.title = title
        self.visibleTitle = visibleTitle
        self.bodyHTML = bodyHTML
        self.stylesheet = stylesheet
        self.manifest = manifest
        self.diagnostics = diagnostics
        self.sourceGeneration = sourceGeneration
        self.preservesRawHTML = preservesRawHTML
    }
}
