import Foundation

/// Resolves authored image references to local resources, applying the export
/// URL policy and packaging bytes into the content-addressed manifest.
///
/// This is a transient builder: it accumulates resources and diagnostics during
/// the single cmark tree walk, then the composer freezes it into an immutable
/// `ExportManifest`. It is deliberately a class (not Sendable) because it is a
/// scratch accumulator local to one composition pass.
final class ExportResourceResolver {
    /// Authored reference URL → resource. Deduplication is by resource identity,
    /// so two references to the same bytes share one resource entry.
    private var resourcesByReference: [String: ExportResource] = [:]
    private(set) var diagnostics: [ExportDiagnostic] = []

    private let documentDirectory: URL?
    /// When true, an unresolved or remote *rendering* resource (image) is a
    /// fatal condition; when false it is reported as a warning and left as
    /// authored. Applies to self-contained HTML and PDF.
    private let unresolvedIsFatal: Bool

    init(documentDirectory: URL?, unresolvedIsFatal: Bool) {
        self.documentDirectory = documentDirectory
        self.unresolvedIsFatal = unresolvedIsFatal
    }

    /// Decides how an authored URL should be rendered. `isImage` distinguishes a
    /// rendering resource (embed/pack) from a navigation link (policy only).
    func disposition(for url: String, isImage: Bool) -> URLDisposition {
        guard ExportURLPolicy.isSafe(url) else {
            return .blank
        }

        // Navigation links to local/remote destinations are left as authored;
        // they are not fetched, embedded, or rewritten.
        guard isImage else {
            return .keep
        }

        // An already-embedded data: image is not a resource we package.
        if let scheme = ExportURLPolicy.scheme(of: url), scheme == "data" {
            return .keep
        }

        // Remote rendering resources are never fetched (offline guarantee).
        if let scheme = ExportURLPolicy.scheme(of: url), ["http", "https"].contains(scheme) {
            return handleUnresolved(url: url, reason: "remote resource is not fetched during offline export")
        }

        // Fragments (in-document anchors) are not resources.
        if url.hasPrefix("#") {
            return .keep
        }

        guard let documentDirectory else {
            return handleUnresolved(url: url, reason: "untitled document has no directory to resolve resources from")
        }

        // Resolve the path, stripping any query/fragment for the filesystem.
        let path = url.split(separator: "#", maxSplits: 1).first.map(String.init) ?? url
        let pathWithoutQuery = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        let fileURL = documentDirectory.appendingPathComponent(pathWithoutQuery).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return handleUnresolved(url: url, reason: "resource does not exist at \(fileURL.lastPathComponent)")
        }

        guard let bytes = try? Data(contentsOf: fileURL) else {
            return handleUnresolved(url: url, reason: "resource could not be read at \(fileURL.lastPathComponent)")
        }

        let mimeType = ExportMIMEType.mimeType(forFileExtension: fileURL.pathExtension)
        let resource = ExportResource(identity: ExportResourceIdentity(bytes: bytes, mimeType: mimeType), bytes: bytes)
        resourcesByReference[url] = resource
        return .rewrite("\(ExportHTMLWriter.assetsDirectoryName)/\(resource.identity.fileName)")
    }

    private func handleUnresolved(url: String, reason: String) -> URLDisposition {
        let message = "Unresolved resource \"\(url)\": \(reason)."
        if unresolvedIsFatal {
            diagnostics.append(ExportDiagnostic(severity: .error, message: message))
        } else {
            diagnostics.append(ExportDiagnostic(severity: .warning, message: message))
        }
        return .keep
    }

    /// Freezes the accumulated resources into a stable manifest. Resources are
    /// deduplicated by identity and ordered deterministically by filename.
    func frozenManifest() -> ExportManifest {
        var byIdentity: [ExportResourceIdentity: ExportResource] = [:]
        for (_, resource) in resourcesByReference where byIdentity[resource.identity] == nil {
            byIdentity[resource.identity] = resource
        }
        let sorted = byIdentity.values.sorted { $0.identity.fileName < $1.identity.fileName }
        return ExportManifest(resources: sorted, referenceMap: resourcesByReference.mapValues { $0.identity.fileName })
    }
}
