import Foundation

/// The completed result of an export: the primary file plus any companion files
/// written alongside it, and the diagnostics produced during composition.
public struct ExportResult: Sendable, Equatable {
    /// The primary output file (the `.html` or `.pdf`).
    public let primaryFile: URL

    /// Companion files written next to the primary file, inside the
    /// document's own `<name>.assets/` directory: image resources and, for
    /// linked-CSS exports, the stylesheet.
    public let companionFiles: [URL]

    /// Composition diagnostics. Always a superset of what the caller can see on
    /// the `PreparedExportDocument`.
    public let diagnostics: [ExportDiagnostic]

    public init(primaryFile: URL, companionFiles: [URL], diagnostics: [ExportDiagnostic]) {
        self.primaryFile = primaryFile
        self.companionFiles = companionFiles
        self.diagnostics = diagnostics
    }
}
