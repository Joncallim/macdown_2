import Foundation

/// Errors surfaced by export composition and writing.
public enum ExportError: Error, CustomStringConvertible {
    /// A self-contained HTML or PDF export encountered a resource that cannot
    /// be embedded (missing local file, or a remote reference that is never
    /// fetched during offline export).
    case unresolvedResources([ExportDiagnostic])
    /// The `ParseExecuting` parse failed.
    case parseFailed(underlying: Error)
    /// The cmark render failed.
    case renderFailed(underlying: Error)
    /// The output could not be written to disk.
    case writeFailed(underlying: Error)
    /// The target directory does not exist and could not be created.
    case invalidDestination(String)

    public var description: String {
        switch self {
        case let .unresolvedResources(diagnostics):
            let messages = diagnostics.map(\.message).joined(separator: "; ")
            return "Export cannot be self-contained: \(messages)"
        case let .parseFailed(error):
            return "Markdown parse failed: \(error.localizedDescription)"
        case let .renderFailed(error):
            return "HTML rendering failed: \(error.localizedDescription)"
        case let .writeFailed(error):
            return "Writing export output failed: \(error.localizedDescription)"
        case let .invalidDestination(path):
            return "Export destination is invalid: \(path)"
        }
    }
}
