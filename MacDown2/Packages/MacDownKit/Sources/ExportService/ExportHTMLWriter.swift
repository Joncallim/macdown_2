import Foundation

/// Renders a `PreparedExportDocument` into a complete HTML document.
///
/// Two output shapes exist:
/// - **Self-contained** — CSS and every resource are embedded in one file
///   (data URIs). Used for the `.selfContained` target and as the PDF input.
/// - **Companion** — resources are referenced as `report.assets/<file>` (written
///   separately), and CSS is either embedded or linked.
public enum ExportHTMLWriter {
    /// The fixed companion directory name for exported resources.
    public static let assetsDirectoryName = "report.assets"

    /// The name of the linked stylesheet companion file.
    public static let linkedStylesheetName = "report.css"

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
        let body = embedResources(in: prepared.bodyHTML, manifest: prepared.manifest)
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
    /// (`<link rel="stylesheet" href="report.css">`) CSS.
    public static func companionHTML(from prepared: PreparedExportDocument, style: ExportStyleEmbedding) -> String {
        let styleElement: String = switch style {
        case .embedded:
            embeddedStyleElement(prepared.stylesheet)
        case .linked:
            "<link rel=\"stylesheet\" href=\"\(linkedStylesheetName)\">"
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

    /// Replaces every `report.assets/<file>` companion reference with its data
    /// URI (`data:<mime>;base64,<bytes>`). Content-addressed filenames are
    /// `<64hex>.<ext>`, so an exact match is deterministic and cannot collide
    /// with authored text.
    ///
    /// The body is scanned once and rebuilt once. Replacing resource by resource
    /// would rescan and recopy the whole document per image — and because each
    /// substitution grows the document by a base64-inflated payload, that copy
    /// gets more expensive with every image an export carries.
    static func embedResources(in body: String, manifest: ExportManifest) -> String {
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
