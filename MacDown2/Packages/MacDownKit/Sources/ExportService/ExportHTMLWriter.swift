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

    /// A complete self-contained HTML document: embedded stylesheet and
    /// resources as data URIs.
    public static func selfContainedHTML(from prepared: PreparedExportDocument) -> String {
        let body = embedResources(in: prepared.bodyHTML, manifest: prepared.manifest)
        let style = embeddedStyleElement(prepared.stylesheet)
        return BuiltInExportTemplate.document(title: prepared.title, styleElement: style, body: body)
    }

    /// A companion HTML document. `style` selects embedded (`<style>`) or linked
    /// (`<link rel="stylesheet" href="report.css">`) CSS.
    public static func companionHTML(from prepared: PreparedExportDocument, style: ExportStyleEmbedding) -> String {
        let styleElement: String = switch style {
        case .embedded:
            embeddedStyleElement(prepared.stylesheet)
        case .linked:
            "<link rel=\"stylesheet\" href=\"report.css\">"
        }
        return BuiltInExportTemplate.document(
            title: prepared.title,
            styleElement: styleElement,
            body: prepared.bodyHTML
        )
    }

    /// The name of the linked stylesheet companion file.
    public static let linkedStylesheetName = "report.css"

    private static func embeddedStyleElement(_ stylesheet: String) -> String {
        "<style>\n\(stylesheet)\n</style>"
    }

    /// Replaces every `report.assets/<file>` companion reference with its data
    /// URI (`data:<mime>;base64,<bytes>`). Content-addressed filenames are
    /// `<64hex>.<ext>`, so an exact string replacement is deterministic and
    /// cannot collide with authored text.
    static func embedResources(in body: String, manifest: ExportManifest) -> String {
        var result = body
        for resource in manifest.resources {
            let fileName = resource.identity.fileName
            let dataURI = "data:\(resource.identity.mimeType);base64,\(resource.bytes.base64EncodedString())"
            result = result.replacingOccurrences(of: "\(assetsDirectoryName)/\(fileName)", with: dataURI)
        }
        return result
    }
}
