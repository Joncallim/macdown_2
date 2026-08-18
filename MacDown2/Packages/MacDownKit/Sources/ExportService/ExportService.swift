import Foundation
import MarkdownEngine

/// The public entry point for first-party Markdown export.
///
/// Composition is split from writing so tests can inspect the frozen
/// `PreparedExportDocument` without touching the filesystem, and so the app's
/// PDF adapter can reuse the same composition and then print it.
///
/// Export remains local and offline: no resource is fetched over the network,
/// and document content is never transmitted to a hosted renderer.
public enum ExportService {
    public static let moduleName = "ExportService"

    /// Composes an export without writing anything. Throws when the target's
    /// policy cannot be satisfied (e.g. a self-contained export with an
    /// unresolved resource).
    public static func prepare(
        _ request: ExportRequest,
        target: ExportTarget,
        engine: any ParseExecuting = ParseEngine()
    ) async throws -> PreparedExportDocument {
        try await ExportComposer.prepare(request: request, target: target, engine: engine)
    }

    /// Composes and writes an HTML export. Returns the written files and the
    /// composition diagnostics.
    public static func exportHTML(
        _ request: ExportRequest,
        to target: ExportTarget,
        engine: any ParseExecuting = ParseEngine()
    ) async throws -> ExportResult {
        guard case .html = target else {
            throw ExportError.invalidDestination("exportHTML writes HTML targets only; use the PDF adapter for PDF")
        }
        let prepared = try await prepare(request, target: target, engine: engine)
        return try ExportFileWriter.writeHTML(prepared, to: target)
    }
}
