import Foundation

/// Errors surfaced by export composition and writing.
///
/// `LocalizedError` is deliberate: the app presents failures with
/// `error.localizedDescription`, which for a bare Swift error is an opaque
/// "operation couldn't be completed" string. Conforming here is what makes the
/// prose below reach the user.
public enum ExportError: Error, LocalizedError, CustomStringConvertible {
    /// A self-contained HTML or PDF export encountered a resource that cannot
    /// be embedded (missing local file, or a remote reference that is never
    /// fetched during offline export).
    case unresolvedResources([ExportDiagnostic])
    /// A self-contained export encountered authored raw HTML. Arbitrary
    /// resource-bearing attributes cannot be proven closed, so the document
    /// must not claim to be self-contained.
    case rawHTMLNotEmbeddable
    /// The `ParseExecuting` parse failed.
    case parseFailed(underlying: Error)
    /// The cmark render failed.
    case renderFailed(underlying: Error)
    /// The output could not be written to disk.
    case writeFailed(underlying: Error)
    /// The target directory does not exist and could not be created.
    case invalidDestination(String)
    /// The document, or what it composes to, is past an export safety gate.
    case budgetExceeded(String)

    public var description: String {
        switch self {
        case let .unresolvedResources(diagnostics):
            let listed = Self.summarise(diagnostics)
            return "This export must embed every image, but some could not be resolved:\n\(listed)"
        case .rawHTMLNotEmbeddable:
            return "This document contains raw HTML, which cannot be embedded in a self-contained file. "
                + "Export it as HTML instead."
        case let .parseFailed(error):
            return "Markdown parse failed: \(error.localizedDescription)"
        case let .renderFailed(error):
            return "HTML rendering failed: \(error.localizedDescription)"
        case let .writeFailed(error):
            return "Writing export output failed: \(error.localizedDescription)"
        case let .invalidDestination(path):
            return "Export destination is invalid: \(path)"
        case let .budgetExceeded(detail):
            return "This document is too large to export: \(detail)."
        }
    }

    public var errorDescription: String? {
        description
    }

    /// How many unresolved resources one message lists before it counts the
    /// rest. A document with two hundred broken images is still one alert.
    private static let listedAtMost = 5

    private static func summarise(_ diagnostics: [ExportDiagnostic]) -> String {
        let listed = diagnostics.prefix(listedAtMost).map(\.message).joined(separator: "\n")
        guard diagnostics.count > listedAtMost else { return listed }
        return listed + "\n…and \(diagnostics.count - listedAtMost) more."
    }

    /// The actionable next step, shown under the message in the app's alert.
    public var recoverySuggestion: String? {
        switch self {
        case .unresolvedResources:
            "Fix the image paths, or export as HTML, which keeps unresolved references as authored."
        case .rawHTMLNotEmbeddable:
            "Choose the HTML format, which preserves authored raw HTML."
        case .parseFailed, .renderFailed:
            nil
        case .writeFailed:
            "Check that the destination folder exists and is writable."
        case .invalidDestination:
            "Choose a different destination folder."
        case .budgetExceeded:
            "Split the document, or reduce the size of the images it references."
        }
    }
}
