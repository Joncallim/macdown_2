import Foundation

/// Writes export output to disk with explicit ownership and primary-last
/// durability (issue #49).
///
/// Ownership contract:
/// - The companion directory is exactly `report.assets` next to the primary
///   file; callers cannot redirect it.
/// - A versioned marker (`report.assets/.macdown-export-marker`) is written
///   before any resource is written, establishing the reserved namespace.
/// - Only the reserved namespace is mutated: the marker, `.tmp` scratch files,
///   and content-addressed `<64hex>.<ext>` resources. Non-reserved user files
///   are never deleted or overwritten.
///
/// Durability contract:
/// - Required resources are written before the primary HTML is atomically
///   promoted, so the HTML never appears before its assets do.
/// - There is no claim of multi-file atomicity; each file is written atomically
///   on its own.
enum ExportFileWriter {
    static let assetsDirectoryName = ExportHTMLWriter.assetsDirectoryName
    static let markerFileName = ".macdown-export-marker"
    static let markerContent = "macdown-export-v1\n"

    /// Writes an HTML export. `target` must be an `.html` target; PDF is written
    /// by the app's WebKit adapter.
    static func writeHTML(_ prepared: PreparedExportDocument, to target: ExportTarget) throws -> ExportResult {
        guard case let .html(url, mode) = target else {
            throw ExportError.invalidDestination("PDF targets are written by the PDF adapter, not the HTML writer")
        }

        let directory = url.deletingLastPathComponent()
        try ensureDirectory(directory)

        var companionFiles: [URL] = []
        let html: String

        switch mode {
        case .selfContained:
            html = ExportHTMLWriter.selfContainedHTML(from: prepared)
        case let .standalone(style):
            html = ExportHTMLWriter.companionHTML(from: prepared, style: style)
            companionFiles = try writeAssets(prepared, nextTo: url)
            if case .linked = style {
                let cssURL = directory.appendingPathComponent(ExportHTMLWriter.linkedStylesheetName)
                try writeAtomically(Data(prepared.stylesheet.utf8), to: cssURL)
                companionFiles.append(cssURL)
            }
        }

        // Primary-last: promote the HTML only after its resources exist.
        try writeAtomically(Data(html.utf8), to: url)

        return ExportResult(primaryFile: url, companionFiles: companionFiles, diagnostics: prepared.diagnostics)
    }

    /// Writes the resource manifest into `report.assets`, marker first. A
    /// document with no resources gets no companion directory: an empty
    /// `report.assets` folder beside every export is litter, not output.
    private static func writeAssets(_ prepared: PreparedExportDocument, nextTo url: URL) throws -> [URL] {
        guard !prepared.manifest.resources.isEmpty else { return [] }

        let directory = url.deletingLastPathComponent()
        let assetsDir = directory.appendingPathComponent(assetsDirectoryName, isDirectory: true)
        try ensureDirectory(assetsDir)

        let markerURL = assetsDir.appendingPathComponent(markerFileName)
        try ensureMarker(at: markerURL)

        var written: [URL] = [markerURL]
        for resource in prepared.manifest.resources {
            let fileURL = assetsDir.appendingPathComponent(resource.identity.fileName)
            try writeAtomically(resource.bytes, to: fileURL)
            written.append(fileURL)
        }
        return written
    }

    private static func ensureMarker(at url: URL) throws {
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == markerContent {
            return
        }
        try writeAtomically(Data(markerContent.utf8), to: url)
    }

    private static func ensureDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ExportError.invalidDestination(url.path)
            }
            return
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ExportError.writeFailed(underlying: error)
        }
    }

    private static func writeAtomically(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ExportError.writeFailed(underlying: error)
        }
    }
}
