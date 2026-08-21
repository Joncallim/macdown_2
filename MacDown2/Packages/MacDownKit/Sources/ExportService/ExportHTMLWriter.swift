import Foundation

/// Renders a `PreparedExportDocument` into a complete HTML document.
///
/// Two output shapes exist:
/// - **Self-contained** — CSS and every resource are embedded in one file
///   (data URIs). Used for the `.selfContained` target and as the PDF input.
/// - **Companion** — resources are referenced as `<name>.assets/<file>` (written
///   separately), and CSS is either embedded or linked.
public enum ExportHTMLWriter {
    /// The companion directory name used when no primary URL is available to
    /// derive one from (a `PreparedExportDocument` built directly by a test, or
    /// any future caller that composes without a destination in hand).
    public static let defaultAssetsDirectoryName = "report.assets"

    /// The per-document companion directory name: the primary file's own
    /// basename.
    ///
    /// Two documents exported into the same folder must never share a
    /// companion directory — sharing one means exporting the second can
    /// overwrite the first's linked stylesheet or leave its resources exposed
    /// to the other's cleanup. Naming the directory after the document it
    /// belongs to makes every export's companions exclusively its own.
    public static func assetsDirectoryName(for primaryURL: URL) -> String {
        let stem = primaryURL.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? defaultAssetsDirectoryName : "\(stem).assets"
    }

    /// The content-addressed resource for the combined stylesheet, used for the
    /// `.linked` CSS delivery.
    ///
    /// Computed fresh from the stylesheet text rather than cached on
    /// `PreparedExportDocument`, so the HTML body's `<link>` reference and the
    /// bytes `ExportFileWriter` writes to disk are always computed the same
    /// way and can never name two different files.
    static func linkedStylesheetResource(for stylesheet: String) -> ExportResource {
        let bytes = Data(stylesheet.utf8)
        return ExportResource(identity: ExportResourceIdentity(bytes: bytes, mimeType: "text/css"), bytes: bytes)
    }

    /// A complete self-contained HTML document: embedded stylesheet and
    /// resources as data URIs.
    ///
    /// `additionalHead` is emitted immediately after `<head>`, ahead of the
    /// title and stylesheet, so a caller can install a document-wide policy
    /// (the PDF adapter's Content-Security-Policy) without rewriting the
    /// rendered markup afterwards.
    public static func selfContainedHTML(
        from prepared: PreparedExportDocument,
        additionalHead: String = ""
    ) -> String {
        let body = embedResources(
            in: prepared.bodyHTML,
            manifest: prepared.manifest,
            assetsDirectoryName: prepared.assetsDirectoryName
        )
        let style = embeddedStyleElement(prepared.stylesheet)
        return BuiltInExportTemplate.document(
            title: prepared.title,
            visibleTitle: prepared.visibleTitle,
            headExtras: additionalHead,
            styleElement: style,
            body: body
        )
    }

    /// A companion HTML document. `style` selects embedded (`<style>`) or linked
    /// (`<link rel="stylesheet" href="<name>.assets/<hash>.css">`) CSS.
    public static func companionHTML(from prepared: PreparedExportDocument, style: ExportStyleEmbedding) -> String {
        let styleElement: String = switch style {
        case .embedded:
            embeddedStyleElement(prepared.stylesheet)
        case .linked:
            linkedStyleElement(prepared)
        }
        return BuiltInExportTemplate.document(
            title: prepared.title,
            visibleTitle: prepared.visibleTitle,
            styleElement: styleElement,
            body: prepared.bodyHTML
        )
    }

    /// 64 hex digits, a dot, and room for any canonical extension.
    private static let maxCompanionNameLength = 96

    private static func embeddedStyleElement(_ stylesheet: String) -> String {
        "<style>\n\(stylesheet)\n</style>"
    }

    private static func linkedStyleElement(_ prepared: PreparedExportDocument) -> String {
        let resource = linkedStylesheetResource(for: prepared.stylesheet)
        let href = "\(prepared.assetsDirectoryName)/\(resource.identity.fileName)"
        return "<link rel=\"stylesheet\" href=\"\(href)\">"
    }

    /// Replaces every `<name>.assets/<file>` companion reference with its data
    /// URI (`data:<mime>;base64,<bytes>`). Content-addressed filenames are
    /// `<64hex>.<ext>`, so an exact match is deterministic and cannot collide
    /// with authored text.
    ///
    /// The body is scanned once and rebuilt once. Replacing resource by resource
    /// would rescan and recopy the whole document per image — and because each
    /// substitution grows the document by a base64-inflated payload, that copy
    /// gets more expensive with every image an export carries.
    static func embedResources(in body: String, manifest: ExportManifest, assetsDirectoryName: String) -> String {
        guard !manifest.resources.isEmpty else { return body }

        var dataURIs: [String: String] = [:]
        dataURIs.reserveCapacity(manifest.resources.count)
        var embeddedBytes = 0
        for resource in manifest.resources {
            let uri = "data:\(resource.identity.mimeType);base64,\(resource.bytes.base64EncodedString())"
            embeddedBytes += uri.utf8.count
            dataURIs[resource.identity.fileName] = uri
        }

        let prefix = "\(assetsDirectoryName)/"
        var result = ""
        result.reserveCapacity(body.utf8.count + embeddedBytes)

        var pending = body.startIndex
        var searchStart = body.startIndex
        while searchStart < body.endIndex,
              let hit = body.range(of: prefix, range: searchStart ..< body.endIndex) {
            // A content-addressed filename is `<64hex>.<ext>`; it ends at the
            // first character that cannot occur in one, which in rendered HTML
            // is the closing attribute quote. The scan is length-bounded so a
            // long alphanumeric run after a false prefix stays cheap.
            let candidate = body[hit.upperBound...]
                .prefix(maxCompanionNameLength)
                .prefix { $0.isLetter || $0.isNumber || $0 == "." }
            guard let uri = dataURIs[String(candidate)] else {
                searchStart = hit.upperBound
                continue
            }
            result += body[pending ..< hit.lowerBound]
            result += uri
            pending = candidate.endIndex
            searchStart = candidate.endIndex
        }

        guard pending != body.startIndex else { return body }
        result += body[pending...]
        return result
    }
}
