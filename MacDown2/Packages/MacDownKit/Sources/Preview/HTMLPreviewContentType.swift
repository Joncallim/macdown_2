import Foundation
import UniformTypeIdentifiers

/// The `Content-Type` of a preview response. A custom-scheme response without one has no MIME type, so
/// WebKit reports `canShowMIMEType == false` for the main document (the navigation-response policy then
/// cancels it and the pane stays blank) and refuses SVG images (`naturalWidth` 0).
public enum HTMLPreviewContentType {
    /// The main document: the host always serves it as UTF-8 (`String` source, or re-encoded hardened HTML).
    public static let mainDocument = "text/html; charset=utf-8"

    public static let fallback = "application/octet-stream"

    /// The MIME type for a served file, from its extension.
    public static func forFileExtension(_ pathExtension: String) -> String {
        let trimmed = pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !trimmed.isEmpty, let mime = UTType(filenameExtension: trimmed)?.preferredMIMEType else {
            return fallback
        }
        return mime
    }

    /// Whether `pathExtension` names an HTML document (served re-hardened).
    public static func isHTML(_ pathExtension: String) -> Bool {
        forFileExtension(pathExtension) == "text/html"
    }
}
