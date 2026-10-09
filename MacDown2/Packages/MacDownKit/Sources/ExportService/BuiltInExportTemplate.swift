import Foundation

/// The single built-in export template.
///
/// macOS 1.0 ships exactly one pure-Swift template; there is no template
/// catalog, no Handlebars dependency, and no custom-template loader. The
/// template variables keep the useful legacy concepts — title, style, content —
/// so migration guidance from old MacDown remains possible, but the layer is a
/// fixed function rather than a pluggable abstraction.
public enum BuiltInExportTemplate {
    /// Renders the complete standalone HTML document shell.
    ///
    /// - Parameters:
    ///   - title: the plain-text document title (HTML-escaped here).
    ///   - visibleTitle: the heading rendered above the body, when front matter
    ///     supplied a title. `nil` emits no heading.
    ///   - headExtras: raw markup emitted first inside `<head>`, before the
    ///     title and stylesheet. The PDF adapter uses it for a
    ///     Content-Security-Policy that must govern the whole document.
    ///   - styleElement: the complete `<style>…</style>` block or
    ///     `<link rel="stylesheet" …>` element for the head.
    ///   - body: the rendered body fragment.
    public static func document(
        title: String,
        visibleTitle: String? = nil,
        headExtras: String = "",
        styleElement: String,
        body: String
    ) -> String {
        let titleTag = title.isEmpty ? "" : "<title>\(HTMLEscaping.escape(title))</title>\n"
        let extras = headExtras.isEmpty ? "" : headExtras + "\n"
        let heading = visibleTitle.map { "<h1>\(HTMLEscaping.escape($0))</h1>\n" } ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(extras)<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
        \(titleTag)\(styleElement)
        </head>
        <body>
        \(heading)\(body)
        </body>
        </html>
        """
    }
}

/// Minimal HTML attribute/text escaping for the few template values E12 owns
/// (title text and generated attribute values). Body and stylesheet bytes are
/// produced by cmark / the bundled stylesheet and are not passed through here.
public enum HTMLEscaping {
    private static let escaped: Set<Unicode.Scalar> = ["&", "<", ">", "\"", "'"]

    /// Per unicode scalar, never per `Character`: a `<`, `>` or `"` preceded by a Prepend scalar (U+0600…) or followed
    /// by a combining mark is merged into one `Character` that matched none of the cases, so it went out unescaped
    /// into `<title>` / the synthesised `<h1>` of a self-contained export.
    public static func escape(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: escaped.contains) else { return text }
        var result = String.UnicodeScalarView()
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result.append(contentsOf: "&amp;".unicodeScalars)
            case "<": result.append(contentsOf: "&lt;".unicodeScalars)
            case ">": result.append(contentsOf: "&gt;".unicodeScalars)
            case "\"": result.append(contentsOf: "&quot;".unicodeScalars)
            case "'": result.append(contentsOf: "&#39;".unicodeScalars)
            default: result.append(scalar)
            }
        }
        return String(result)
    }
}
